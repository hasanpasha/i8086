fetcher: Fetcher,

pub const Fetcher = struct {
    ctx: ?*anyopaque,
    fetch_fn: *const fn (ctx: ?*anyopaque) ?u8,

    pub fn fetch(self: @This(), comptime size: Size) ?size.T() {
        const lo = self.fetch_fn(self.ctx) orelse return null;
        return if (size == .b)
            lo
        else
            (@as(u16, self.fetch_fn(self.ctx) orelse return null) << 8) | lo;
    }
};

pub const AddressingModeByte = packed struct(u8) {
    /// Register/Memory
    rm: u3,

    /// Register index
    reg: u3,

    /// Adressing Mode
    mod: u2,

    pub fn from(val: u8) @This() {
        return @bitCast(val);
    }
};

fn decodeOperandsFromAMB(self: Self, amb: AddressingModeByte, w: u1, d: u1) !struct { Operand, Operand } {
    const op1: Operand, const op2: Operand = .{ .{ .reg = .ofNumAndSize(amb.reg, w) }, switch (amb.mod) {
        0b11 => .{ .reg = .ofNumAndSize(amb.rm, w) },
        else => .{
            .mem = .{
                .base = switch (amb.rm) {
                    0, 1, 7 => .bx,
                    2, 3 => .bp,
                    4, 5 => null,
                    6 => if (amb.mod != 0) .bp else null,
                },
                .index = switch (amb.rm) {
                    0, 2, 4 => .si,
                    1, 3, 5 => .di,
                    6, 7 => null,
                },
                .disp = switch (amb.mod) {
                    0b00 => if (amb.rm == 6) @bitCast(try self.fetch(.w)) else 0,
                    0b01 => @intCast(try self.fetch(.b)),
                    0b10 => @bitCast(try self.fetch(.w)),
                    else => 0,
                },
                .segment_override = switch (amb.rm) {
                    2, 3 => .ss,
                    6 => if (amb.mod != 0) .ss else null,
                    else => null,
                },
                .size = .from(w),
            },
        },
    } };

    return switch (d) {
        0 => .{ op2, op1 },
        1 => .{ op1, op2 },
    };
}

/// fetch Adressing Mode Byte
pub fn fetchAMB(self: Self) !AddressingModeByte {
    return .from(try self.fetch(.b));
}

fn signExtend(val: u8) u16 {
    return @bitCast(@as(i16, @as(i8, @bitCast(val))));
}

fn decodeOpToOpInstr(self: Self, comptime instr_tag: @EnumLiteral(), opcode: u8) !Instruction {
    const d: u1 = @truncate((opcode >> 1) & 1);
    const w: u1 = @truncate(opcode & 1);

    const op1, const op2 = try self.decodeOperandsFromAMB(try self.fetchAMB(), w, d);
    return @unionInit(Instruction, @tagName(instr_tag), .{ .op1 = op1, .op2 = op2 });
}

fn fetch(self: Self, comptime size: Size) error{not_enough_data}!size.T() {
    return self.fetcher.fetch(size) orelse return error.not_enough_data;
}

pub fn decode(self: Self) !?Instruction {
    const opcode = self.fetcher.fetch(.b) orelse return null;

    return switch (opcode) {
        0x00...0x04 => try self.decodeOpToOpInstr(.add, opcode),
        0x08...0x0B => try self.decodeOpToOpInstr(.or_, opcode),
        0x20...0x23 => try self.decodeOpToOpInstr(.and_, opcode),
        0x24, 0x25 => val: {
            const w: u1 = @truncate(opcode & 1);

            const reg: Register = switch (w) {
                0 => .al,
                1 => .ax,
            };

            const ac: Operand = .{ .reg = reg };

            const data: Operand = switch (w) {
                0 => .{ .imm8 = try self.fetch(.b) },
                1 => .{ .imm16 = try self.fetch(.w) },
            };

            break :val .{ .and_ = .{ .op1 = ac, .op2 = data } };
        },
        0x28...0x2B => try self.decodeOpToOpInstr(.sub, opcode),
        0x30...0x33 => try self.decodeOpToOpInstr(.xor, opcode),
        0x38...0x3B => try self.decodeOpToOpInstr(.cmp, opcode),
        0x40...0x47 => .{ .inc = .{ .reg = .ofNumAndSize(@truncate(opcode), 1) } },
        0x48...0x4F => .{ .dec = .{ .reg = .ofNumAndSize(@truncate(opcode), 1) } },
        0x50...0x57 => .{ .push = .{ .reg = .ofNumAndSize(@truncate(opcode), 1) } },
        0x58...0x5F => .{ .pop = .{ .reg = .ofNumAndSize(@truncate(opcode), 1) } },
        0x70...0x7F => .{ .jc = .{ .cond = @enumFromInt(opcode & 0xF), .rel = @bitCast(try self.fetch(.b)) } },
        0x80 => val: {
            const w: u1 = @truncate(opcode & 1);
            const amb: AddressingModeByte = try self.fetchAMB();

            _, const op1 = try self.decodeOperandsFromAMB(amb, w, 0);

            const op2: Operand = switch (w) {
                0 => .{ .imm8 = try self.fetch(.b) },
                1 => .{ .imm16 = try self.fetch(.w) },
            };

            const bin: Instruction.Binary = .{ .op1 = op1, .op2 = op2 };

            break :val switch (amb.reg) {
                0b100 => .{ .and_ = bin },
                else => std.debug.panic("unhandled {b}", .{amb.reg}),
            };
        },
        0x83 => val: {
            const amb: AddressingModeByte = try self.fetchAMB();
            _, const op1 = try self.decodeOperandsFromAMB(amb, 1, 0);

            const kk = try self.fetch(.b);
            const jjkk = signExtend(kk);
            const op2: Operand = .{ .imm16 = jjkk };

            const bin: Instruction.Binary = .{ .op1 = op1, .op2 = op2 };

            break :val switch (amb.reg) {
                0b000 => .{ .add = bin },
                0b111 => .{ .cmp = bin },
                0b101 => .{ .sub = bin },
                else => std.debug.panic("unsupported word-sign extended operation: {b}", .{amb.reg}),
            };
        },
        0x88...0x8B => try self.decodeOpToOpInstr(.mov, opcode),
        0x8E => val: {
            const amb: AddressingModeByte = try self.fetchAMB();
            _, const src = try self.decodeOperandsFromAMB(amb, 1, 0);

            const seg_reg: Register = switch (@as(u2, @truncate(amb.reg))) {
                0b00 => .es,
                0b01 => .cs,
                0b10 => .ss,
                0b11 => .ds,
            };
            const dst: Operand = .{ .reg = seg_reg };

            break :val .{ .mov = .{ .op1 = dst, .op2 = src } };
        },
        0x90 => .nop,
        0x9E => .sahf,
        0x9F => .lahf,
        0xA4 => .{ .movs = .b },
        0xA5 => .{ .movs = .w },
        0xAA => .{ .stos = .b },
        0xAB => .{ .stos = .w },
        0xAC => .{ .lods = .b },
        0xAD => .{ .lods = .w },
        0xB0...0xBF => val: { // MOV reg, data
            const w: u1 = @truncate((opcode >> 3) & 1);
            const rrr: u3 = @truncate(opcode & 0b111);

            const dst_reg: Register = .ofNumAndSize(rrr, w);
            const dst: Operand = .{ .reg = dst_reg };

            const src: Operand = switch (w) {
                0 => .{ .imm8 = try self.fetch(.b) },
                1 => .{ .imm16 = try self.fetch(.w) },
            };

            break :val .{ .mov = .{ .op1 = dst, .op2 = src } };
        },
        0xC3 => .{ .ret = .{ .disp16 = try self.fetch(.w) } },
        0xC6, 0xC7 => val: { // MOV mem, imm
            const w: u1 = @truncate(opcode & 1);
            const op1, _ = try self.decodeOperandsFromAMB(try self.fetchAMB(), w, 0);

            const op2: Operand = switch (w) {
                0 => .{ .imm8 = try self.fetch(.b) },
                1 => .{ .imm16 = try self.fetch(.w) },
            };

            break :val .{ .mov = .{ .op1 = op1, .op2 = op2 } };
        },
        0xE8 => .{ .call = .{ .disp16 = try self.fetch(.w) } },
        0xE9 => .{ .jmp = .{ .disp16 = try self.fetch(.w) } },
        0xEA => val: {
            const ip = try self.fetch(.w);
            const cs = try self.fetch(.w);
            break :val .{ .jmp = .{ .addr = .{ .ip = ip, .cs = cs } } };
        },
        0xEB => .{ .jmp = .{ .disp = @bitCast(try self.fetch(.b)) } },
        0xFA => .cli,
        0xF4 => .hlt,
        0xFC => .cld,
        0xFD => .std,
        else => std.debug.panic("unknown opcode {X}", .{opcode}),
    };
}

const Self = @This();

const std = @import("std");

const Instruction = @import("instruction.zig").Instruction;
const Operand = Instruction.Operand;
const Register = Instruction.Register;
const Size = @import("size.zig").Size;

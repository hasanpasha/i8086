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

fn decodeOperandsFromAMB(chip: *Chip, amb: AddressingModeByte, w: u1, d: u1) struct { Operand, Operand } {
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
                    0b00 => if (amb.rm == 6) @bitCast(chip.fetchWord()) else 0,
                    0b01 => @intCast(chip.fetchByte()),
                    0b10 => @bitCast(chip.fetchWord()),
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
        0 => .{ op1, op2 },
        1 => .{ op2, op1 },
    };
}

/// fetch Adressing Mode Byte
pub fn fetchAMB(chip: *Chip) AddressingModeByte {
    return .from(chip.fetchByte());
}

fn signExtend(val: u8) u16 {
    return @bitCast(@as(i16, @as(i8, @bitCast(val))));
}

pub fn decode(chip: *Chip) struct { u16, Instruction } {
    const prev_ip = chip.ip;
    defer chip.ip = prev_ip;

    const opcode = chip.fetchByte();

    const instr: Instruction = switch (opcode) {
        0x00...0x04 => val: { // ADD mem/reg1, mem/reg2
            const d: u1 = @truncate((opcode >> 1) & 1);
            const w: u1 = @truncate(opcode & 1);

            const op2, const op1 = decodeOperandsFromAMB(chip, fetchAMB(chip), w, d);
            break :val .{ .add = .{ .op1 = op1, .op2 = op2 } };
        },
        0x08...0x0B => val: { // OR mem/reg1, mem/reg2
            const d: u1 = @truncate((opcode >> 1) & 1);
            const w: u1 = @truncate(opcode & 1);

            const op2, const op1 = decodeOperandsFromAMB(chip, fetchAMB(chip), w, d);
            break :val .{ .or_ = .{ .op1 = op1, .op2 = op2 } };
        },
        0x20...0x23 => val: {
            const d: u1 = @truncate((opcode >> 1) & 1);
            const w: u1 = @truncate(opcode & 1);

            const op2, const op1 = decodeOperandsFromAMB(chip, fetchAMB(chip), w, d);
            break :val .{ .and_ = .{ .op1 = op1, .op2 = op2 } };
        },
        0x24, 0x25 => val: {
            const w: u1 = @truncate(opcode & 1);

            const reg: Register = switch (w) {
                0 => .al,
                1 => .ax,
            };

            const ac: Operand = .{ .reg = reg };

            const data: Operand = switch (w) {
                0 => .{ .imm8 = chip.fetchByte() },
                1 => .{ .imm16 = chip.fetchWord() },
            };

            break :val .{ .and_ = .{ .op1 = ac, .op2 = data } };
        },
        0x40...0x47 => .{ .inc = .{ .reg = .ofNumAndSize(@truncate(opcode), 1) } },
        0x48...0x4F => .{ .dec = .{ .reg = .ofNumAndSize(@truncate(opcode), 1) } },
        0x70...0x7F => .{ .jc = .{ .cond = @enumFromInt(opcode & 0xF), .rel = @bitCast(chip.fetchByte()) } },
        0x80 => val: {
            const w: u1 = @truncate(opcode & 1);
            const amb: AddressingModeByte = fetchAMB(chip);

            _, const op1 = decodeOperandsFromAMB(chip, amb, w, 0);

            const op2: Operand = switch (w) {
                0 => .{ .imm8 = chip.fetchByte() },
                1 => .{ .imm16 = chip.fetchWord() },
            };

            const bin: Instruction.Binary = .{ .op1 = op1, .op2 = op2 };

            break :val switch (amb.reg) {
                0b100 => .{ .and_ = bin },
                else => std.debug.panic("unhandled {b}", .{amb.reg}),
            };
        },
        0x83 => val: {
            const amb: AddressingModeByte = fetchAMB(chip);
            _, const op1 = decodeOperandsFromAMB(chip, amb, 1, 0);

            const kk = chip.fetchByte();
            const jjkk = signExtend(kk);
            const op2: Operand = .{ .imm16 = jjkk };

            const bin: Instruction.Binary = .{ .op1 = op1, .op2 = op2 };

            break :val switch (amb.reg) {
                0b111 => .{ .cmp = bin },
                0b101 => .{ .sub = bin },
                else => std.debug.panic("unsupported word-sign extended operation: {b}", .{amb.reg}),
            };
        },
        0x88...0x8B => val: { // MOV mem/reg1, mem/reg2
            const d: u1 = @truncate((opcode >> 1) & 1);
            const w: u1 = @truncate(opcode & 1);

            const src, const dst = decodeOperandsFromAMB(chip, fetchAMB(chip), w, d);
            break :val .{ .mov = .{ .src = src, .dst = dst } };
        },
        0x8E => val: {
            const amb: AddressingModeByte = fetchAMB(chip);

            _, const src = decodeOperandsFromAMB(chip, amb, 1, 0);

            const seg_reg: Register = switch (@as(u2, @truncate(amb.reg))) {
                0b00 => .es,
                0b01 => .cs,
                0b10 => .ss,
                0b11 => .ds,
            };
            const dst: Operand = .{ .reg = seg_reg };

            break :val .{ .mov = .{ .src = src, .dst = dst } };
        },
        0x9E => .sahf,
        0x9F => .lahf,
        0xA4 => .{ .movs = .b },
        0xA5 => .{ .movs = .w },
        0xB0...0xBF => val: { // MOV reg, data
            const w: u1 = @truncate((opcode >> 3) & 1);
            const rrr: u3 = @truncate(opcode & 0b111);

            const dst_reg: Register = .ofNumAndSize(rrr, w);
            const dst: Operand = .{ .reg = dst_reg };

            const src: Operand = switch (w) {
                0 => .{ .imm8 = chip.fetchByte() },
                1 => .{ .imm16 = chip.fetchWord() },
            };

            break :val .{ .mov = .{ .src = src, .dst = dst } };
        },
        0xC6 => val: {
            const w: u1 = @truncate((opcode >> 3) & 1);
            _, const op1 = decodeOperandsFromAMB(chip, fetchAMB(chip), w, 0);

            const op2: Operand = switch (w) {
                0 => .{ .imm8 = chip.fetchByte() },
                1 => .{ .imm16 = chip.fetchWord() },
            };

            break :val .{ .mov = .{ .src = op2, .dst = op1 } };
        },
        0xE9 => .{ .jmp = .{ .disp16 = chip.fetchWord() } },
        0xEB => .{ .jmp = .{ .disp = @bitCast(chip.fetchByte()) } },
        0xF4 => .hlt,
        0xFC => .cld,
        0xFD => .std,
        else => std.debug.panic("unknown opcode {X}", .{opcode}),
    };

    return .{ chip.ip - prev_ip, instr };
}

const std = @import("std");

const root = @import("root.zig");
const Chip = root.Chip;
const Instruction = root.Instruction;
const Operand = Instruction.Operand;
const Register = Instruction.Register;

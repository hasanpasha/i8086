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

pub const DecodedInstr = struct {
    u16,
    Instruction,
};

fn decodeOperandsFromAddressModeByte(chip: *Chip, w: u1, d: u1) struct { Operand, Operand } {
    const amb: AddressingModeByte = .from(chip.fetchByte());

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

pub fn decode(chip: *Chip) DecodedInstr {
    const prev_ip = chip.ip;
    defer chip.ip = prev_ip;

    const opcode = chip.fetchByte();

    const instr: Instruction = switch (opcode) {
        0x00...0x04 => val: { // ADD mem/reg1, mem/reg2
            const d: u1 = @truncate((opcode >> 1) & 1);
            const w: u1 = @truncate(opcode & 1);

            const op2, const op1 = decodeOperandsFromAddressModeByte(chip, w, d);
            break :val .{ .add = .{ .op1 = op1, .op2 = op2 } };
        },
        0x88...0x8B => val: { // MOV mem/reg1, mem/reg2
            const d: u1 = @truncate((opcode >> 1) & 1);
            const w: u1 = @truncate(opcode & 1);

            const src, const dst = decodeOperandsFromAddressModeByte(chip, w, d);
            break :val .{ .mov = .{ .src = src, .dst = dst } };
        },
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
        0xE9 => .{ .jmp = .{ .disp16 = chip.fetchWord() } },
        0xEB => .{ .jmp = .{ .disp = @bitCast(chip.fetchByte()) } },
        0xF4 => .hlt,
        else => std.debug.panic("unknown opcode {X}", .{opcode}),
    };

    return .{ chip.ip - prev_ip, instr };
}

const std = @import("std");

const root = @import("root.zig");
const Chip = root.Chip;
const Instruction = root.Instruction;
const Operand = Instruction.Operand;
const Register = Operand.Register;

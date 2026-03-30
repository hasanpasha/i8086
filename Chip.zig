registers: [std.meta.fields(Register).len]u16,

/// instruction pointer (program counter)
ip: u16,

/// flags register
flags: Flags,

bus: MemoryBus,

halted: bool = false,

// /// user function to read from port
// port_in_fn: *const fn (ctx: ?*anyopaque, port: u8) u8,

// /// user function to write to port
// port_out_fn: *const fn (ctx: ?*anyopaque, port: u8, value: u8) void,

// /// user custom data pointer
// userdata: ?*anyopaque,

pub const Flags = packed struct(u16) {
    /// Carry
    c: u1,

    _1: u1,

    /// parity
    p: u1,

    _2: u1,

    /// auxiliary carry
    a: u1,

    _3: u1,

    /// zero
    z: u1,

    /// sign
    s: u1,

    /// trap
    t: u1,

    /// interrupt enable/disable
    i: u1,

    /// direction
    d: u1,

    /// overflow
    o: u1,

    _4: u4,

    pub fn format(self: Flags, writer: *Writer) Writer.Error!void {
        const fields = std.meta.fields(Flags);
        inline for (fields) |field| {
            if (field.name[0] == '_') continue;
            try writer.print("{s}({}) ", .{ field.name, @field(self, field.name) });
        }
    }
};

const Self = @This();

pub fn init(bus: MemoryBus) Self {
    var self: Self = undefined;

    self.ip = 0;

    self.setReg(.w, .cs, 0);
    self.setReg(.w, .ds, 0xFF);

    self.bus = bus;

    return self;
}

pub fn format(self: Self, writer: *Writer) Writer.Error!void {
    try writer.print("IP:0x{X} flags:{f} ", .{ self.ip, self.flags });
    const fields = std.meta.fields(Register);
    inline for (fields, 0..) |field, idx| {
        const whole = self.registers[idx];
        try writer.print("{s}:0x{X:0>4}", .{ field.name, whole });
        if (idx < fields.len) try writer.writeByte(' ');
    }
}

pub fn getReg(self: *const Self, comptime size: Size, reg: Register) size.T() {
    const reg_whole: *const u16 = &self.registers[reg.idx()];

    const val: size.T() = switch (size) {
        .b => val: {
            const reg_parts: *const [2]u8 = @ptrCast(reg_whole);
            const part: usize = switch (reg) {
                .a, .b, .c, .d => |p| if (p == .l) 0 else 1,
                else => 0,
            };
            break :val reg_parts[part];
        },
        .w => reg_whole.*,
    };

    std.log.debug("{f} -> {X}", .{ reg, val });
    return val;
}

pub fn setReg(self: *Self, comptime size: Size, reg: Register, val: size.T()) void {
    std.log.debug("{f} <- {X}", .{ reg, val });

    const reg_whole: *u16 = &self.registers[reg.idx()];

    switch (size) {
        .b => {
            const reg_parts: *[2]u8 = @ptrCast(reg_whole);
            switch (reg) {
                .a, .b, .c, .d => |v| reg_parts[if (v == .h) 1 else 0] = val,
                else => reg_parts[0] = val,
            }
        },
        .w => reg_whole.* = val,
    }
}

fn linearAddr(self: *const Self, seg: Register, effective_addr: u16) u20 {
    return (@as(u20, self.getReg(.w, seg)) << 4) +% effective_addr;
}

pub fn readMem(self: *const Self, comptime size: Size, addr: u20) size.T() {
    return switch (size) {
        .b => self.bus.read(addr),
        .w => val: {
            const lo = self.bus.read(addr);
            const hi = self.bus.read(addr +% 1);
            break :val @as(u16, hi) << 8 | lo;
        },
    };
}

pub fn writeMem(self: *Self, comptime size: Size, addr: u20, val: size.T()) void {
    self.bus.write(addr, @truncate(val));
    if (size == .w)
        self.bus.write(addr +% 1, @truncate(val >> 8));
}

pub fn fetchByte(self: *Self) u8 {
    const byte = self.readMem(.b, self.linearAddr(.cs, self.ip));
    self.ip +%= 1;
    return byte;
}

pub fn fetchWord(self: *Self) u16 {
    const lo = self.fetchByte();
    const hi = self.fetchByte();
    return @as(u16, hi) << 8 | lo;
}

fn getAddrOfMemoryOperand(self: *const Self, mem: Operand.Memory) u20 {
    const segment_reg: Register = if (mem.segment_override) |segment| segment else .ds;

    const effective_addr: u16 = val: {
        var res: i16 = 0;

        if (mem.base) |base|
            res +%= @as(i16, @bitCast(self.getReg(.w, base)));

        if (mem.index) |index|
            res +%= @as(i16, @bitCast(self.getReg(.w, index)));

        res +%= mem.disp;

        break :val @bitCast(res);
    };

    return self.linearAddr(segment_reg, effective_addr);
}

fn getOperand(self: *const Self, comptime size: Size, operand: Operand) size.T() {
    return switch (operand) {
        .imm8 => |imm| @intCast(imm),
        .imm16 => |imm| @intCast(imm),
        .reg => |reg| self.getReg(size, reg),
        .mem => |mem| self.readMem(size, self.getAddrOfMemoryOperand(mem)),
    };
}

fn setOperand(self: *Self, comptime size: Size, operand: Operand, val: size.T()) void {
    switch (operand) {
        .imm8, .imm16 => unreachable,
        .reg => |reg| self.setReg(size, reg, val),
        .mem => |mem| self.writeMem(size, self.getAddrOfMemoryOperand(mem), val),
    }
}

pub const ALUFlags = packed struct(u16) {
    /// Carry
    c: ?u1 = null,

    /// parity
    p: ?u1 = null,

    /// auxiliary carry
    a: ?u1 = null,

    /// zero
    z: ?u1 = null,

    /// sign
    s: ?u1 = null,

    /// trap
    t: ?u1 = null,

    /// interrupt enable/disable
    i: ?u1 = null,

    /// direction
    d: ?u1 = null,

    /// overflow
    o: ?u1 = null,

    _: u7 = 0,
};

// TODO: handle flags
fn add(a: anytype, b: @TypeOf(a)) struct { @TypeOf(a), ALUFlags } {
    return .{ a +% b, .{} };
}

// const BinaryExecutor = fn (self: *Self, a: anytype, b: anytype) @TypeOf(a);

fn execBinary(self: *Self, bin: Instruction.Binary, comptime executor: anytype) void {
    const new_flags: ALUFlags = switch (bin.op1.size()) {
        .b => flags: {
            const result, const new_flags = executor(self.getOperand(.b, bin.op1), self.getOperand(.b, bin.op2));
            self.setOperand(.b, bin.op1, result);
            break :flags new_flags;
        },
        .w => flags: {
            const result, const new_flags = executor(self.getOperand(.w, bin.op1), self.getOperand(.w, bin.op2));
            self.setOperand(.w, bin.op1, result);
            break :flags new_flags;
        },
    };
    _ = new_flags;
}

fn execute(self: *Self, instr: Instruction) void {
    switch (instr) {
        .hlt => self.halted = true,
        .add => |bin| self.execBinary(bin, add),
        .mov => |mov| switch (mov.dst.size()) {
            .b => self.setOperand(.b, mov.dst, self.getOperand(.b, mov.src)),
            .w => self.setOperand(.w, mov.dst, self.getOperand(.w, mov.src)),
        },
        .jmp => |jmp| switch (jmp) {
            .disp => |rel| self.ip = @bitCast(@as(i16, @bitCast(self.ip)) + rel),
            .disp16 => |val| self.ip +%= val,
        },
    }
}

pub fn step(self: *Self) void {
    const size, const instr = decoder.decode(self);
    std.log.debug("{f}", .{instr});

    self.ip += size;
    self.execute(instr);
}

const std = @import("std");
const Writer = std.Io.Writer;

const root = @import("root.zig");

const MemoryBus = root.MemoryBus;

const decoder = root.decoder;
const Instruction = root.Instruction;
const Operand = Instruction.Operand;
const Register = Operand.Register;
const Size = root.Size;

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
    c: bool,

    _1: u1,

    /// parity
    p: bool,

    _2: bool,

    /// auxiliary carry
    a: bool,

    _3: u1,

    /// zero
    z: bool,

    /// sign
    s: bool, //0b11000001

    /// trap
    t: bool,

    /// interrupt enable/disable
    i: bool,

    /// direction
    d: bool,

    /// overflow
    o: bool,

    _4: u4,

    pub fn getLow(self: Flags) u8 {
        return @truncate(@as(u16, @bitCast(self)) & 0xFF);
    }

    pub fn setLow(self: *Flags, val: u8) void {
        std.log.debug("before: {f}", .{self.*});

        const raw_p: *[2]u8 = @ptrCast(@alignCast(self));
        raw_p[0] = val;

        std.log.debug("flags: {f}", .{self.*});
    }

    pub fn format(self: Flags, writer: *Writer) Writer.Error!void {
        const fields = std.meta.fields(Flags);
        inline for (fields) |field| {
            if (field.name[0] == '_') continue;
            if (@field(self, field.name)) {
                try writer.print("{c}F ", .{std.ascii.toUpper(field.name[0])});
            } else {
                try writer.print("{c}f ", .{std.ascii.toLower(field.name[0])});
            }
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
    const val: size.T() = switch (size) {
        .b => self.bus.read(addr),
        .w => val: {
            const lo = self.bus.read(addr);
            const hi = self.bus.read(addr +% 1);
            break :val @as(u16, hi) << 8 | lo;
        },
    };

    std.log.debug("[{X:0>4}] -> {X:0>" ++ (if (size == .b) "2" else "4") ++ "}", .{ addr, val });
    return val;
}

pub fn writeMem(self: *Self, comptime size: Size, addr: u20, val: size.T()) void {
    std.log.debug("[{X:0>4}] <- {X:0>" ++ (if (size == .b) "2" else "4") ++ "}", .{ addr, val });

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

fn execBinary(self: *Self, bin: Instruction.Binary, comptime executor: anytype) void {
    const new_flags: alu.Flags = switch (bin.op1.size()) {
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

    std.log.debug("old_flags: {f}", .{self.flags});
    defer std.log.debug("new_flags: {f}", .{self.flags});

    inline for (std.meta.fields(alu.Flags)) |field| {
        if (@field(new_flags, field.name)) |new_value| {
            @field(self.flags, field.name) = new_value;
        }
    }
}

fn jmpRelative(self: *Self, rel: i8) void {
    self.ip = @bitCast(@as(i16, @bitCast(self.ip)) + rel);
}

fn execute(self: *Self, instr: Instruction) void {
    switch (instr) {
        .hlt => self.halted = true,
        .add => |bin| self.execBinary(bin, alu.add),
        .sub => |bin| self.execBinary(bin, alu.sub),
        .and_ => |bin| self.execBinary(bin, alu.anD),
        .or_ => |bin| self.execBinary(bin, alu.oR),
        .mov => |mov| switch (mov.dst.size()) {
            .b => self.setOperand(.b, mov.dst, self.getOperand(.b, mov.src)),
            .w => self.setOperand(.w, mov.dst, self.getOperand(.w, mov.src)),
        },
        .movs => |size| {
            const si: u16 = self.getReg(.w, .si);
            const di: u16 = self.getReg(.w, .di);
            const src_addr = self.linearAddr(.ds, si);
            const dst_addr = self.linearAddr(.es, di);

            const offset: i3 = switch (size) {
                .b => offset: {
                    self.writeMem(.b, dst_addr, self.readMem(.b, src_addr));
                    break :offset if (self.flags.d) -1 else 1;
                },
                .w => offset: {
                    self.writeMem(.w, dst_addr, self.readMem(.w, src_addr));
                    break :offset if (self.flags.d) -2 else 2;
                },
            };

            const new_si: u16 = @bitCast(@as(i16, @bitCast(si)) +% offset);
            const new_di: u16 = @bitCast(@as(i16, @bitCast(di)) +% offset);

            std.log.debug("si: {X:0>4} -> {X:0>4}", .{ si, new_si });
            std.log.debug("di: {X:0>4} -> {X:0>4}", .{ di, new_di });

            self.setReg(.w, .si, new_si);
            self.setReg(.w, .di, new_di);
        },
        .jmp => |jmp| switch (jmp) {
            .disp => |rel| self.jmpRelative(rel),
            .disp16 => |val| self.ip +%= val,
        },
        .jc => |cond_jmp| {
            const should_jmp = switch (cond_jmp.cond) {
                .o => self.flags.o,
                .no => !self.flags.o,
                .b => self.flags.c,
                .ae => !self.flags.c,
                .e => self.flags.z,
                .ne => !self.flags.z,
                .be => self.flags.c or self.flags.z,
                .a => !self.flags.c and !self.flags.z,
                .s => self.flags.s,
                .ns => !self.flags.s,
                .np => !self.flags.p,
                .p => self.flags.p,
                .l => self.flags.s != self.flags.o,
                .ge => self.flags.s == self.flags.o,
                .le => self.flags.z or self.flags.s != self.flags.o,
                .g => !self.flags.z and self.flags.s == self.flags.o,
            };

            if (should_jmp) self.jmpRelative(cond_jmp.rel);
        },
        // clear direction flag
        .cld => self.flags.d = false,
        // set direction flag
        .std => self.flags.d = true,
        .inc => |op| self.execBinary(.{ .op1 = op, .op2 = .{ .imm16 = 1 } }, alu.inc),
        .dec => |op| self.execBinary(.{ .op1 = op, .op2 = .{ .imm16 = 1 } }, alu.dec),
        .cmp => |bin| self.execBinary(bin, alu.cmp),
        .sahf => self.flags.setLow(self.getReg(.b, .al)),
        .lahf => self.setReg(.b, .al, @truncate(@as(u16, @bitCast(self.flags)) & 0xFF)),
    }
}

pub fn fetchInstr(self: *Self) Instruction {
    const size, const instr = decoder.decode(self);
    self.ip +%= size;

    return instr;
}

pub fn step(self: *Self) void {
    const instr = self.fetchInstr();
    std.log.info("{f}", .{instr});

    self.execute(instr);
}

pub fn spin(self: *Self) void {
    while (!self.halted) {
        self.step();
    }
}

const std = @import("std");
const Writer = std.Io.Writer;

const root = @import("root.zig");

const MemoryBus = root.MemoryBus;

const decoder = root.decoder;
const alu = root.alu;
const Instruction = root.Instruction;
const Operand = Instruction.Operand;
const Register = Instruction.Register;
const Size = root.Size;

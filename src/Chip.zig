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

pub const Flags = packed union(u16) {
    raw: u16,

    v: packed struct(u16) {
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
        s: bool,

        /// trap
        t: bool,

        /// interrupt enable/disable
        i: bool,

        /// direction
        d: bool,

        /// overflow
        o: bool,

        _4: u4,

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            inline for (std.meta.fields(@This())) |field| {
                if (field.name[0] == '_') continue;

                if (@field(self, field.name)) {
                    try writer.print("{c}F ", .{std.ascii.toUpper(field.name[0])});
                } else {
                    try writer.print("{c}f ", .{field.name[0]});
                }
            }
        }
    },

    pub fn getLow(self: Flags) u8 {
        return @truncate(self.raw & 0xFF);
    }

    pub fn setLow(self: *Flags, val: u8) void {
        log.debug("old_flags: {f}", .{self});
        defer log.debug("new_flags: {f}", .{self});

        self.raw = (self.raw & 0xFF00) | val;
    }

    pub fn updateFromALUFlags(self: *Flags, alu_flags: alu.Flags) void {
        log.debug("old_flags: {f}", .{self});
        defer log.debug("new_flags: {f}", .{self});

        inline for (std.meta.fields(alu.Flags)) |field| {
            if (@field(alu_flags, field.name)) |new_value| {
                @field(self.v, field.name) = new_value;
            }
        }
    }

    pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
        try writer.print("{f}", .{self.v});
    }
};

const Self = @This();

pub fn init(bus: MemoryBus) Self {
    var self: Self = undefined;

    self.bus = bus;

    self.reset();

    return self;
}

pub fn reset(self: *Self) void {
    self.flags.raw = 0;

    self.ip = 0x0000;
    self.setReg(.w, .cs, 0xFFFF);

    self.setReg(.w, .ds, 0x0000);
    self.setReg(.w, .ss, 0x0000);
    self.setReg(.w, .es, 0x0000);
}

pub fn format(self: Self, writer: *Writer) Writer.Error!void {
    try writer.print("IP:{X:0>4} flags:{f} ", .{ self.ip, self.flags });
    const fields = std.meta.fields(Register);
    inline for (fields, 0..) |field, idx| {
        const whole = self.registers[idx];
        try writer.print("{s}:{X:0>4}", .{ field.name, whole });
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

    log.debug("{f} -> {X}", .{ reg, val });
    return val;
}

pub fn setReg(self: *Self, comptime size: Size, reg: Register, val: size.T()) void {
    log.debug("{f} <- {X}", .{ reg, val });

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
    const segment_addr = self.getReg(.w, seg);
    return (@as(u20, segment_addr) << 4) +% effective_addr;
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

    log.debug("[{X:0>5}] -> {X:0>" ++ (if (size == .b) "2" else "4") ++ "}", .{ addr, val });
    return val;
}

pub fn writeMem(self: *Self, comptime size: Size, addr: u20, val: size.T()) void {
    log.debug("[{X:0>5}] <- {X:0>" ++ (if (size == .b) "2" else "4") ++ "}", .{ addr, val });

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

fn execBinaryTyped(self: *Self, comptime size: Size, bin: Instruction.Binary, comptime executor: anytype) void {
    const op1 = self.getOperand(size, bin.op1);
    const op2 = self.getOperand(size, bin.op2);

    const result, const alu_flags = executor(op1, op2);
    self.setOperand(size, bin.op1, result);
    self.flags.updateFromALUFlags(alu_flags);
}

fn execBinary(self: *Self, bin: Instruction.Binary, comptime executor: anytype) void {
    switch (bin.size()) {
        .b => self.execBinaryTyped(.b, bin, executor),
        .w => self.execBinaryTyped(.w, bin, executor),
    }
}

fn jmpRelative(self: *Self, rel: i8) void {
    self.ip = @bitCast(@as(i16, @bitCast(self.ip)) + rel);
}

fn push(self: *Self, comptime size: Size, value: size.T()) void {
    const sp: u16 = self.getReg(.w, .sp);

    const new_sp = sp -% (if (size == .b) 1 else 2);
    self.setReg(.w, .sp, new_sp);

    const addr = self.linearAddr(.ss, new_sp);
    self.writeMem(size, addr, value);
}

fn pushOperand(self: *Self, op: Operand) void {
    switch (op.size()) {
        .b => self.push(.b, self.getOperand(.b, op)),
        .w => self.push(.w, self.getOperand(.w, op)),
    }
}

fn pop(self: *Self, comptime size: Size) size.T() {
    const sp: u16 = self.getReg(.w, .sp);

    const new_sp = sp +% (if (size == .b) 1 else 2);
    self.setReg(.w, .sp, new_sp);

    const addr = self.linearAddr(.ss, sp);
    return self.readMem(size, addr);
}

fn popOperand(self: *Self, dst: Operand) void {
    switch (dst.size()) {
        .b => self.setOperand(.b, dst, self.pop(.b)),
        .w => self.setOperand(.w, dst, self.pop(.w)),
    }
}

fn loadAtSI(self: *Self, comptime size: Size) size.T() {
    const si = self.getReg(.w, .si);

    const bytes = @sizeOf(size.T());
    const offset: i3 = if (self.flags.v.d) -bytes else bytes;
    self.setReg(.w, .si, @bitCast(@as(i16, @bitCast(si)) +% offset));

    return self.readMem(size, self.linearAddr(.ds, si));
}

fn storeAtDI(self: *Self, comptime size: Size, value: size.T()) void {
    const di = self.getReg(.w, .di);

    const bytes = @sizeOf(size.T());
    const offset: i3 = if (self.flags.v.d) -bytes else bytes;
    self.setReg(.w, .di, @bitCast(@as(i16, @bitCast(di)) +% offset));

    self.writeMem(size, self.linearAddr(.es, di), value);
}

fn execute(self: *Self, instr: Instruction) void {
    switch (instr) {
        .hlt => self.halted = true,
        .add => |bin| self.execBinary(bin, alu.add),
        .sub => |bin| self.execBinary(bin, alu.sub),
        .and_ => |bin| self.execBinary(bin, alu.anD),
        .or_ => |bin| self.execBinary(bin, alu.oR),
        .xor => |bin| self.execBinary(bin, alu.xor),
        .cmp => |bin| self.execBinary(bin, alu.cmp),
        .mov => |mov| switch (mov.dst.size()) {
            .b => self.setOperand(.b, mov.dst, self.getOperand(.b, mov.src)),
            .w => self.setOperand(.w, mov.dst, self.getOperand(.w, mov.src)),
        },
        .movs => |size| switch (size) {
            .b => self.storeAtDI(.b, self.loadAtSI(.b)),
            .w => self.storeAtDI(.w, self.loadAtSI(.w)),
        },
        .stos => |size| switch (size) {
            .b => self.storeAtDI(.b, self.getReg(.b, .al)),
            .w => self.storeAtDI(.w, self.getReg(.w, .ax)),
        },
        .lods => |size| switch (size) {
            .b => self.setReg(.b, .al, self.loadAtSI(.b)),
            .w => self.setReg(.w, .ax, self.loadAtSI(.w)),
        },
        .jmp => |jmp| switch (jmp) {
            .addr => |addr| {
                self.ip = addr.ip;
                self.setReg(.w, .cs, addr.cs);
            },
            .disp => |rel| self.jmpRelative(rel),
            .disp16 => |disp| self.ip +%= disp,
        },
        .jc => |cond_jmp| {
            const should_jmp = switch (cond_jmp.cond) {
                .o => self.flags.v.o,
                .no => !self.flags.v.o,
                .b => self.flags.v.c,
                .ae => !self.flags.v.c,
                .e => self.flags.v.z,
                .ne => !self.flags.v.z,
                .be => self.flags.v.c or self.flags.v.z,
                .a => !self.flags.v.c and !self.flags.v.z,
                .s => self.flags.v.s,
                .ns => !self.flags.v.s,
                .np => !self.flags.v.p,
                .p => self.flags.v.p,
                .l => self.flags.v.s != self.flags.v.o,
                .ge => self.flags.v.s == self.flags.v.o,
                .le => self.flags.v.z or self.flags.v.s != self.flags.v.o,
                .g => !self.flags.v.z and self.flags.v.s == self.flags.v.o,
            };

            if (should_jmp) self.jmpRelative(cond_jmp.rel);
        },
        // clear direction flag
        .cld => self.flags.v.d = false,
        // set direction flag
        .std => self.flags.v.d = true,
        // clear interrupt flag
        .cli => self.flags.v.i = false,
        .inc => |op| self.execBinary(
            .{ .op1 = op, .op2 = .{ .imm16 = 1 } },
            alu.inc,
        ),
        .dec => |op| self.execBinary(
            .{ .op1 = op, .op2 = .{ .imm16 = 1 } },
            alu.dec,
        ),
        .sahf => self.flags.setLow(self.getReg(.b, .al)),
        .lahf => self.setReg(.b, .al, self.flags.getLow()),
        .push => |op| self.pushOperand(op),
        .pop => |op| self.popOperand(op),
        .call => |call| {
            switch (call) {
                .disp16 => |disp| {
                    self.push(.w, self.ip);
                    self.ip +%= disp;
                },
            }
        },
        .ret => |ret| {
            switch (ret) {
                .disp16 => |disp| {
                    self.ip = self.pop(.w);
                    const sp = self.getReg(.w, .sp);
                    const new_sp = sp +% disp;
                    self.setReg(.w, .sp, new_sp);
                },
            }
        },
    }
}

pub fn fetchInstr(self: *Self) Instruction {
    const size, const instr = decoder.decode(self);
    self.ip +%= size;

    return instr;
}

pub fn step(self: *Self) void {
    const instr = self.fetchInstr();
    log.info("{f}", .{instr});

    self.execute(instr);
}

pub fn spin(self: *Self) void {
    while (true) {
        while (self.halted) {}

        self.step();
    }
}

const log = std.log.scoped(.chip);

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

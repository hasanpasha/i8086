pub const Instruction = union(enum) {
    hlt,
    cld,
    std,
    cli,
    sahf,
    lahf,
    nop,
    mov: Binary,
    add: Binary,
    sub: Binary,
    and_: Binary,
    or_: Binary,
    xor: Binary,
    cmp: Binary,
    inc: Operand,
    dec: Operand,
    push: Operand,
    pop: Operand,
    movs: Size,
    stos: Size,
    lods: Size,
    jmp: Jmp,
    jc: CondJmp,
    call: Call,
    ret: Return,

    pub const Return = union(enum) {
        disp16: u16,

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            switch (self) {
                .disp16 => |disp| try writer.print("ret {}", .{disp}),
            }
        }
    };

    pub const Call = union(enum) {
        // addr: Addr,
        // mem,
        disp16: u16,
        // mem_reg,

        pub const Addr = struct {
            pc: u16,
            cs: u16,
        };

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            switch (self) {
                .disp16 => |disp| try writer.print("call {}", .{disp}),
            }
        }
    };

    pub const CondJmp = struct {
        cond: Cond,
        rel: i8,

        pub const Cond = enum(u4) {
            /// Overflow
            o = 0x0,

            /// Not Overflow
            no = 0x1,

            /// Below/Not Above or Equal
            b = 0x2,

            /// Above or Equal/Not Below
            ae = 0x3,

            /// Equal
            e = 0x4,

            /// Not Equal/Not Zero
            ne = 0x5,

            /// Below or Equal/Not Above
            be = 0x6,

            /// Above/Not Below or Equal
            a = 0x7,

            /// Sign
            s = 0x8,

            /// Not Sign
            ns = 0x9,

            /// Parity/Parity Even
            p = 0xA,

            /// No Parity/Parity Odd
            np = 0xB,

            /// Less/Not Greater or Equal
            l = 0xC,

            /// Not Less/Greater or Equal
            ge = 0xD,

            /// Less or Equal
            le = 0xE,

            /// Great/Not Less or Equal
            g = 0xF,
        };

        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("j{s} {}", .{ @tagName(self.cond), self.rel });
        }
    };

    pub const Register = union(enum) {
        // general purpose registers

        /// (=ah, al) primary accumulator(s)
        a: Part,

        /// (=bl, hl) accumulator(s) and base register
        b: Part,

        /// (=cl, ch) accumulator(s) and counter
        c: Part,

        /// (=dl, dh) accumulator(s) and I/O address
        d: Part,

        // pointer registers

        /// stack pointer
        sp,

        /// base pointer
        bp,

        // index registers

        /// source index
        si,

        /// destination index
        di,

        // segment registers

        /// code segment
        cs,

        /// data segment
        ds,

        /// stack segment
        ss,

        /// extra segment
        es,

        pub const Part = enum {
            l,
            h,
            x,
        };

        pub const al: Register = .{ .a = .l };
        pub const bl: Register = .{ .b = .l };
        pub const cl: Register = .{ .c = .l };
        pub const dl: Register = .{ .d = .l };

        pub const ah: Register = .{ .a = .h };
        pub const bh: Register = .{ .b = .h };
        pub const ch: Register = .{ .c = .h };
        pub const dh: Register = .{ .d = .h };

        pub const ax: Register = .{ .a = .x };
        pub const bx: Register = .{ .b = .x };
        pub const cx: Register = .{ .c = .x };
        pub const dx: Register = .{ .d = .x };

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            switch (self) {
                .a, .b, .c, .d => |p| try writer.print("{s}{s}", .{ @tagName(self), @tagName(p) }),
                inline else => try writer.print("{s}", .{@tagName(self)}),
            }
        }

        pub fn idx(self: Register) usize {
            const tag = std.meta.activeTag(self);
            return @intCast(@intFromEnum(tag));
        }

        pub fn ofNumAndSize(rrr: u3, w: u1) Register {
            return switch (rrr) {
                0 => if (w == 0) .al else .ax,
                1 => if (w == 0) .cl else .cx,
                2 => if (w == 0) .dl else .dx,
                3 => if (w == 0) .bl else .bx,
                4 => if (w == 0) .ah else .sp,
                5 => if (w == 0) .ch else .bp,
                6 => if (w == 0) .dh else .si,
                7 => if (w == 0) .bh else .di,
            };
        }

        pub fn size(self: Register) Size {
            return switch (self) {
                .a, .b, .c, .d => |part| if (part == .x) .w else .b,
                else => .w,
            };
        }
    };

    pub const Operand = union(enum) {
        imm8: u8,
        imm16: u16,
        reg: Register,
        mem: Memory,

        pub const Memory = struct {
            segment_override: ?Register = null,
            base: ?Register = null,
            index: ?Register,
            disp: i16 = 0,
            size: Size,

            pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
                if (self.segment_override) |seg|
                    try writer.print("{f}:", .{seg});

                try writer.writeAll("[");

                if (self.base) |base| {
                    try writer.print("{f}", .{base});

                    if (self.index != null or self.disp != 0)
                        try writer.writeAll(" + ");
                }

                if (self.index) |index| {
                    try writer.print("{f}", .{index});

                    if (self.disp != 0)
                        try writer.writeAll(" + ");
                }

                if (self.disp != 0 or (self.segment_override == null and self.base == null and self.index == null))
                    try writer.print("{d:05}", .{self.disp});

                try writer.writeAll("]");
            }
        };

        pub fn size(self: @This()) Size {
            return switch (self) {
                .imm8 => .b,
                .imm16 => .w,
                .reg => |reg| reg.size(),
                .mem => |mem| mem.size,
            };
        }

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            switch (self) {
                .imm8 => |val| try writer.print("{X:0>2}", .{val}),
                .imm16 => |val| try writer.print("{X:0>4}", .{val}),
                inline else => |val| try writer.print("{f}", .{val}),
            }
        }
    };

    pub const Binary = struct {
        op1: Operand,
        op2: Operand,

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            try writer.print("{t} {f}, {f}", .{ self.op1.size(), self.op1, self.op2 });
        }

        pub fn size(self: @This()) Size {
            return self.op1.size();
        }
    };

    pub const Jmp = union(enum) {
        addr: Addr,
        disp: i8,
        disp16: u16,

        pub const Addr = struct {
            ip: u16,
            cs: u16,
        };

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            switch (self) {
                .addr => |addr| try writer.print("jmp {X:0>4}:{X:0>4}", .{ addr.cs, addr.ip }),
                inline else => |val| try writer.print("jmp {X}", .{val}),
            }
        }
    };

    pub fn format(self: Instruction, writer: *Writer) Writer.Error!void {
        switch (self) {
            .hlt => try writer.writeAll("hlt"),
            .mov, .add, .sub, .cmp, .xor => |bin, tag| try writer.print("{s}{f}", .{ @tagName(tag), bin }),
            .and_ => |bin| try writer.print("and{f}", .{bin}),
            .or_ => |bin| try writer.print("or{f}", .{bin}),
            .movs, .stos, .lods => |size, tag| try writer.print("{s}{s}", .{ @tagName(tag), @tagName(size) }),
            .inc, .dec, .push, .pop => |op, tag| try writer.print("{s} {f}", .{ @tagName(tag), op }),
            .cld, .std, .lahf, .sahf, .cli, .nop => |_, tag| try writer.print("{s}", .{@tagName(tag)}),
            inline else => |instr| try writer.print("{f}", .{instr}),
        }
    }
};

const std = @import("std");
const Writer = std.Io.Writer;

const Size = @import("size.zig").Size;

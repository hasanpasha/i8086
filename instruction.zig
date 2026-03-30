pub const Instruction = union(enum) {
    add: Binary,
    hlt,
    jmp: Jmp,
    mov: Mov,

    pub const Operand = union(enum) {
        imm8: u8,
        imm16: u16,
        reg: Register,
        mem: Memory,

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

                if (self.disp != 0)
                    try writer.print("{X}", .{self.disp});

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
    };

    pub const Jmp = union(enum) {
        disp: i8,
        disp16: u16,

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            switch (self) {
                inline else => |val| try writer.print("jmp {X}", .{val}),
            }
        }
    };

    pub const Mov = struct {
        src: Operand,
        dst: Operand,

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            try writer.print("mov{t} {f}, {f}", .{ self.dst.size(), self.dst, self.src });
        }
    };

    pub fn format(self: Instruction, writer: *Writer) Writer.Error!void {
        switch (self) {
            .hlt => try writer.writeAll("hlt"),
            .add => |bin| try writer.print("add{f}", .{bin}),
            inline else => |instr| try writer.print("{f}", .{instr}),
        }
    }
};

const std = @import("std");
const Writer = std.Io.Writer;

const Size = @import("size.zig").Size;

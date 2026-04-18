pub const Flags = struct {
    /// Carry
    c: ?bool = null,

    /// parity
    p: ?bool = null,

    /// auxiliary carry
    a: ?bool = null,

    /// zero
    z: ?bool = null,

    /// sign
    s: ?bool = null,

    /// trap
    t: ?bool = null,

    /// overflow
    o: ?bool = null,
};

fn parity(result: anytype) bool {
    return @popCount(@as(u8, @truncate(result))) % 2 == 0;
}

fn addCore(comptime T: type, a: T, b: T, carry_in: bool) struct { T, bool } {
    const bits = @bitSizeOf(T);
    const Wide = @Int(.unsigned, bits + 1);

    const wide_result: Wide = @as(Wide, a) + @as(Wide, b) + @as(Wide, @intFromBool(carry_in));
    const result: T = @truncate(wide_result);

    return .{ result, (wide_result >> bits) != 0 };
}

fn computeFlags(T: type, a: T, b: T, result: T, carry_out: bool) Flags {
    const bits = @bitSizeOf(T);
    const sign_mask = @as(T, 1) << (bits - 1);

    return .{
        .a = ((a ^ b ^ result) & 0x10) != 0,
        .c = carry_out,
        .o = ((~(a ^ b) & (a ^ result)) & sign_mask) != 0,
        .z = result == 0,
        .s = (result & sign_mask) != 0,
        .p = parity(result),
    };
}

fn innerAdd(comptime T: type, a: T, b: T, carry_in: bool) struct { T, Flags } {
    const result, const carry_out = addCore(T, a, b, carry_in);
    const flags = computeFlags(T, a, b, result, carry_out);
    return .{ result, flags };
}

pub fn add(a: anytype, b: @TypeOf(a)) struct { @TypeOf(a), Flags } {
    return innerAdd(@TypeOf(a), a, b, false);
}

pub fn sub(a: anytype, b: @TypeOf(a)) struct { @TypeOf(a), Flags } {
    return innerAdd(@TypeOf(a), a, ~b, true);
}

pub fn inc(a: anytype, b: @TypeOf(a)) struct { @TypeOf(a), Flags } {
    const result, var flags = add(a, b);
    flags.c = null;
    return .{ result, flags };
}

pub fn dec(a: anytype, b: @TypeOf(a)) struct { @TypeOf(a), Flags } {
    const result, var flags = sub(a, b);
    flags.c = null;
    return .{ result, flags };
}

pub fn cmp(a: anytype, b: @TypeOf(a)) struct { @TypeOf(a), Flags } {
    _, const flags = sub(a, b);
    return .{ a, flags };
}

fn computeBitFlags(result: anytype) Flags {
    const bits = @bitSizeOf(@TypeOf(result));
    const sign_mask = @as(@TypeOf(result), 1) << (bits - 1);
    return Flags{
        .c = false,
        .o = false,
        .z = result == 0,
        .s = (result & sign_mask) != 0,
        .p = parity(result),
    };
}

pub fn anD(a: anytype, b: @TypeOf(a)) struct { @TypeOf(a), Flags } {
    const result = a & b;
    return .{ result, computeBitFlags(result) };
}

pub fn oR(a: anytype, b: @TypeOf(a)) struct { @TypeOf(a), Flags } {
    const result = a | b;
    return .{ result, computeBitFlags(result) };
}

const eql = std.testing.expectEqualDeep;

test "add" {
    try eql(add(@as(u8, 0b1111_1111), @as(u8, 0b0000_0001)), .{ @as(u8, 0b0000_0000), Flags{
        .a = true,
        .c = true,
        .o = false,
        .z = true,
        .s = false,
        .p = true,
    } });
    try eql(add(@as(u8, 0b0111_1111), 0b0000_0001), .{ 0b1000_0000, Flags{
        .a = true,
        .c = false,
        .o = true,
        .z = false,
        .s = true,
        .p = false,
    } });

    try eql(add(@as(u16, 0b1111_0000_0111_1111), 0b1000_0000_1010_0000), .{ 0b0111_0001_0001_1111, Flags{
        .a = false,
        .c = true,
        .o = true,
        .z = false,
        .s = false,
        .p = false,
    } });

    try eql(add(@as(u16, 0b0000_0000_0010_1001), 0b0000_0100_1110_1101), .{ 0b0000_0101_0001_0110, Flags{
        .a = true,
        .c = false,
        .o = false,
        .z = false,
        .s = false,
        .p = false,
    } });
}

test "and" {
    try eql(anD(@as(u8, 0b0000_0110), 0b1111_0001), .{ 0b00000000, Flags{
        .c = false,
        .o = false,
        .z = true,
        .s = false,
        .p = true,
    } });
    try eql(anD(@as(u8, 0b0100_0111), 0b0101_0010), .{ 0b0100_0010, Flags{
        .c = false,
        .o = false,
        .z = false,
        .s = false,
        .p = true,
    } });
}

const std = @import("std");

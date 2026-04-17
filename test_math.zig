pub fn main() !void {
    const a: u8 = 0b0111_1111;
    const b: u8 = 0b0000_0001;
    const result = a +% b;

    // ((~(a ^ b) & (a ^ result)) & 0x80) != 0;
    const x1 = (a ^ b);
    const x2 = ~x1;
    const x3 = a ^ result;
    const x4 = x2 & x3;
    const x5 = x4 & 0x80;
    const overflow = x5 != 0;

    std.log.debug("a = {b:0>8}, b = {b:0>8}, result = {b:0>8}", .{ a, b, result });
    std.log.debug("(a ^ b) = {b:0>8}, ~(a ^ b) = {b:0>8}, (a ^ result) = {b:0>8}", .{ x1, x2, x3 });
    std.log.debug("~(a ^ b) & (a ^ result) = {b:0>8}", .{x4});
    std.log.debug("(~(a ^ b) & (a ^ result)) & 0x80 = {}", .{x5});
    std.log.debug("overflow = {}", .{overflow});
}

const std = @import("std");

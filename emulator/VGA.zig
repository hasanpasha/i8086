pub fn read(self: *const Self, addr: u20) u8 {
    _ = self;
    _ = addr;
    return 0xAB;
}

pub fn write(self: *Self, addr: u20, val: u8) void {
    _ = self;
    _ = addr;
    _ = val;
}

const Self = @This();

const log = std.log.scoped(.vga);
const std = @import("std");

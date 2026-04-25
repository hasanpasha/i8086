ctx: ?*anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    read_fn: *const fn (ctx: ?*anyopaque, addr: u20) u8,
    write_fn: *const fn (ctx: ?*anyopaque, addr: u20, data: u8) void,
};

pub fn read(self: @This(), comptime size: Size, addr: u20) size.T() {
    const data = self.vtable.read_fn(self.ctx, addr);
    return switch (size) {
        .b => data,
        .w => (@as(u16, self.vtable.read_fn(self.ctx, addr +% 1)) << 8) | data,
    };
}

pub fn write(self: @This(), comptime size: Size, addr: u20, data: size.T()) void {
    self.vtable.write_fn(self.ctx, addr, @truncate(data));
    if (size == .w)
        self.vtable.write_fn(self.ctx, addr +% 1, @truncate(data >> 8));
}

const Size = @import("root.zig").Size;

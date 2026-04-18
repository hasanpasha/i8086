ctx: ?*anyopaque,
vtable: *const VTable,

const Self = @This();

pub const VTable = struct {
    read_fn: *const fn (ctx: ?*anyopaque, addr: u20) u8,
    write_fn: *const fn (ctx: ?*anyopaque, addr: u20, value: u8) void,
};

pub fn read(self: Self, addr: u20) u8 {
    return self.vtable.read_fn(self.ctx, addr);
}

pub fn write(self: Self, addr: u20, value: u8) void {
    self.vtable.write_fn(self.ctx, addr, value);
}

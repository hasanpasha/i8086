start: u20,
end: u20,
ctx: ?*anyopaque,
vtable: *const VTable,

const Self = @This();

pub const VTable = struct {
    read_fn: *const fn (ctx: ?*anyopaque, addr: u20) u8,
    write_fn: *const fn (ctx: ?*anyopaque, addr: u20, value: u8) void,
};

pub fn offset(self: Self, addr: u20) u20 {
    return addr - self.start;
}

pub fn read(self: Self, addr: u20) u8 {
    return self.vtable.read_fn(self.ctx, self.offset(addr));
}

pub fn write(self: Self, addr: u20, value: u8) void {
    self.vtable.write_fn(self.ctx, self.offset(addr), value);
}

pub const EmptyRegion = struct {
    start: u20,
    end: u20,

    pub fn init(start: u20, end: u20) EmptyRegion {
        return .{ .start = start, .end = end };
    }

    fn empty_read(ctx: *anyopaque, addr: u20) u8 {
        _ = ctx;
        _ = addr;
        return 0xAA;
    }

    fn empty_write(ctx: *anyopaque, addr: u20, val: u8) void {
        _ = ctx;
        _ = addr;
        _ = val;
    }

    pub const vtable = VTable{
        .read_fn = &empty_read,
        .write_fn = &empty_write,
    };

    pub fn region(self: *@This()) @This() {
        return .{
            .start = self.start,
            .end = self.end,
            .ctx = self,
            .vtable = &vtable,
        };
    }
};

mem: [1 << 20]u8 = undefined,

pub fn loadAt(self: *@This(), path: []const u8, index: usize) !void {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();

    const file_size = try f.getEndPos();

    if (file_size > self.mem.len)
        return error.too_big_bin;

    const dest = self.mem[index .. index + file_size];

    if (try f.readAll(dest) != file_size)
        return error.read_size_not_match;
}

fn read(ctx: ?*anyopaque, addr: u20) u8 {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    return self.mem[@intCast(addr)];
}

fn write(ctx: ?*anyopaque, addr: u20, val: u8) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.mem[@intCast(addr)] = val;
}

const vtable: MemoryBus.VTable = .{
    .read_fn = &read,
    .write_fn = &write,
};

pub fn memoryBus(self: *@This()) MemoryBus {
    return .{
        .ctx = self,
        .vtable = &vtable,
    };
}

const std = @import("std");

const root = @import("root.zig");
const MemoryBus = root.MemoryBus;

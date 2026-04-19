mem: [0xFFFF]u8,

pub fn loadAt(self: *@This(), io: std.Io, path: []const u8) !void {
    var file_task = io.async(std.Io.Dir.openFile, .{ .cwd(), io, path, .{} });
    defer if (file_task.cancel(io)) |file| file.close(io) else |_| {};

    const f: std.Io.File = try file_task.await(io);

    const file_size: usize = @intCast((try f.stat(io)).size);

    std.log.debug("file size: {X}, rom size: {X}", .{ file_size, self.mem.len });

    if (file_size > self.mem.len)
        return error.file_too_large;

    const offset = self.mem.len - file_size;

    const dst = self.mem[offset..self.mem.len];

    std.log.debug("offset: {X}", .{offset});

    const read_size = try f.readPositionalAll(io, dst, 0);

    std.log.debug("file size: {X}, read size: {X}", .{ file_size, read_size });

    if (read_size != file_size)
        return error.read_size_not_match;

    std.log.debug("{X}", .{self.mem[0..0xFF]});
}

fn read(ctx: ?*anyopaque, addr: u20) u8 {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    return self.mem[@intCast(addr)];
}

fn write(_: ?*anyopaque, _: u20, _: u8) void {
    std.debug.panic("can't write into ROM memory", .{});
}

pub const vtable = MemoryRegion.VTable{
    .read_fn = &read,
    .write_fn = &write,
};

pub fn region(self: *@This()) MemoryRegion {
    return .{
        .start = 0xF0000,
        .end = 0xFFFFF,
        .ctx = self,
        .vtable = &vtable,
    };
}

const std = @import("std");
const MemoryRegion = @import("MemoryRegion.zig");

mem: [1 << 20]u8 = undefined,

pub fn loadAt(self: *@This(), io: std.Io, path: []const u8, index: usize) !void {
    var file_task = io.async(std.Io.Dir.openFile, .{ .cwd(), io, path, .{} });
    defer if (file_task.cancel(io)) |file| file.close(io) else |_| {};

    const f: std.Io.File = try file_task.await(io);

    const file_size = (try f.stat(io)).size;

    if (file_size > self.mem.len)
        return error.too_big_bin;

    const dest = self.mem[index .. index + file_size];

    if (try f.readPositionalAll(io, dest, 0) != file_size)
        return error.read_size_not_match;
}

pub fn fmt(ctx: struct { @This(), usize, usize }, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const self, const start, const offset = ctx;

    const each = 32;
    const unit_size = 2;

    var i: usize = start;
    const end: usize = start + offset;

    while (i <= end) : (i += each) {
        try writer.print("[{X:0>5}] ", .{i});

        for (0..each / unit_size) |j| {
            const l = i + j * unit_size;

            for (0..unit_size) |p| {
                try writer.print("{X:0>2}", .{self.mem[l + p]});
            }
            try writer.writeAll(" ");
        }

        if (i < end)
            try writer.writeByte('\n');
    }
}

pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try fmt(.{ self, 0, self.mem.len }, writer);
}

pub fn dumpMem(self: @This(), start: usize, offset: usize) std.fmt.Alt(struct { @This(), usize, usize }, fmt) {
    return .{ .data = .{ self, start, offset } };
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

pub const Fetcher = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    idx: usize = 0,

    pub fn loadFromFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !Fetcher {
        var file_task = io.async(std.Io.Dir.openFile, .{ .cwd(), io, path, .{} });
        defer if (file_task.cancel(io)) |file| file.close(io) else |_| {};

        const f: std.Io.File = try file_task.await(io);

        const file_size: usize = @intCast((try f.stat(io)).size);

        const mem = try allocator.alloc(u8, file_size);

        if (file_size > mem.len)
            return error.file_too_large;

        const read_size = try f.readPositionalAll(io, mem, 0);

        if (read_size != file_size)
            return error.read_size_not_match;

        return .{ .allocator = allocator, .data = mem };
    }

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.data);
    }

    fn fetch(ctx: ?*anyopaque) ?u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.idx >= self.data.len) return null;
        defer self.idx += 1;
        return self.data[self.idx];
    }

    pub fn fetcher(self: *@This()) Decoder.Fetcher {
        return .{ .ctx = self, .fetch_fn = &fetch };
    }
};

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();

    const program = args.next() orelse unreachable;

    const binary_path = args.next() orelse
        std.debug.panic("usage: {s} <FILE>", .{program});

    log.info("disassmbling {s}", .{binary_path});

    var fetcher: Fetcher = try .loadFromFile(init.io, init.gpa, binary_path);
    defer fetcher.deinit();

    const decoder = Decoder{ .fetcher = fetcher.fetcher() };

    while (try decoder.decode()) |instr|
        log.info("{f}", .{instr});
}

const std = @import("std");
const log = std.log.scoped(.disassmbler);

const Decoder = @import("I8086").Decoder;

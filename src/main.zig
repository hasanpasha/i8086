pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();

    const program = args.next() orelse unreachable;

    const binary_path = args.next() orelse
        std.debug.panic("usage: {s} <FILE>", .{program});

    log.info("emulating {s}", .{binary_path});

    var ram: RAM = .{};
    try ram.loadAt(init.io, binary_path, 0);

    var chip: Chip = .init(ram.memoryBus());
    chip.spin();
}

const std = @import("std");
const log = std.log.scoped(.main);
const I8086 = @import("I8086");
const Chip = I8086.Chip;
const RAM = I8086.RAM;

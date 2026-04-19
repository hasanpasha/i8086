pub const std_options: std.Options = .{
    .log_level = .debug,
};

var ram: RAM = undefined;
var rom: ROM = undefined;

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();

    const program = args.next() orelse unreachable;

    const binary_path = args.next() orelse
        std.debug.panic("usage: {s} <FILE>", .{program});

    log.info("emulating {s}", .{binary_path});

    try rom.loadAt(init.io, binary_path);

    const bus: MemoryBus = .{ .regions = &.{ ram.region(), rom.region() } };

    var chip: Chip = .init(bus);
    chip.spin();
}

const std = @import("std");
const log = std.log.scoped(.main);
const I8086 = @import("I8086");
const Chip = I8086.Chip;
// const RAM = I8086.RAM;
const MemoryBus = I8086.MemoryBus;
const MemoryRegion = I8086.MemoryRegion;
const RAM = I8086.RAM;
const ROM = I8086.ROM;

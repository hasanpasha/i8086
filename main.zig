pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main() !void {
    var args = std.process.args();

    const program = args.next() orelse unreachable;

    const binary_path = args.next() orelse
        std.debug.panic("usage: {s} <FILE>", .{program});

    var ram: RAM = .{};
    try ram.loadAt(binary_path, 0);

    var chip: Chip = .init(ram.memoryBus());
    while (!chip.halted) {
        chip.step();
    }
}

const std = @import("std");
const I8086 = @import("I8086");
const Chip = I8086.Chip;
const RAM = I8086.RAM;

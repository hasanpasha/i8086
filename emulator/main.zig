pub const std_options: std.Options = .{
    .log_level = .debug,
    .log_scope_levels = &.{
        .{ .scope = .bus, .level = .err },
    },
};

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();

    const program = args.next() orelse unreachable;

    const binary_path = args.next() orelse
        std.debug.panic("usage: {s} <FILE>", .{program});

    log.info("emulating {s}", .{binary_path});

    var ibm_bus: IBMBus = try .init(init.io, init.gpa, binary_path);
    defer ibm_bus.deinit();

    const chip = try CPU.init(init.gpa, ibm_bus.bus());
    chip.spin();
}

const std = @import("std");
const log = std.log.scoped(.emulator);

const I8086 = @import("I8086");
const CPU = I8086.CPU;

const IBMBus = @import("IBMBus.zig");

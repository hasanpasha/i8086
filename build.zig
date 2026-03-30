const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const i8086_mod = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_exe = b.addExecutable(.{
        .name = "test_emu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "I8086", .module = i8086_mod },
            },
        }),
    });

    b.installArtifact(test_exe);

    const tiny_test_bin = b.addSystemCommand(&.{ "nasm", "-f", "bin", "tiny_test.S", "-o", "tiny_test.bin" });

    const run_test = b.addRunArtifact(test_exe);
    if (b.args) |args|
        run_test.addArgs(args);

    run_test.step.dependOn(&tiny_test_bin.step);

    b.step("test", "run test roms").dependOn(&run_test.step);
}

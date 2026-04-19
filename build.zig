const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_math_exe = b.addExecutable(.{
        .name = "test_math",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_math.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.step("test-math", "test-math").dependOn(&b.addRunArtifact(test_math_exe).step);

    const i8086_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "8086emu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "I8086", .module = i8086_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args|
        run_exe.addArgs(args);

    b.step("run", "run the emulator").dependOn(&run_exe.step);

    const test_run = b.addTest(.{ .root_module = i8086_mod });
    b.step("test", "run unit tests").dependOn(&test_run.step);

    const nasm_files: []const []const u8 = comptime &.{
        // "tiny_test.S",
        // "mov.S",
        // "add.S",
        // "and.S",
        // "or.S",
        "helloworld.S",
    };

    const rom_test_step = b.step("rom-test", "run test roms");
    inline for (nasm_files) |asm_name| {
        const asm_path = "asm_src/" ++ asm_name;
        const bin_path = asm_path ++ ".bin";
        const build_bin = b.addSystemCommand(&.{ "nasm", "-f", "bin", asm_path, "-o", bin_path });
        const run = b.addRunArtifact(exe);
        run.addArg(bin_path);
        run.step.dependOn(&build_bin.step);
        rom_test_step.dependOn(&run.step);
    }
}

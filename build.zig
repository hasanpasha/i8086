const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const i8086_mod = b.createModule(.{
        .root_source_file = b.path("i8080/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const i8080dis_exe = b.addExecutable(.{
        .name = "8080dis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("disassmbler/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "I8086", .module = i8086_mod },
            },
        }),
    });

    const i8080emu_exe = b.addExecutable(.{
        .name = "8086emu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("emulator/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "I8086", .module = i8086_mod },
            },
        }),
    });

    b.installArtifact(i8080dis_exe);
    b.installArtifact(i8080emu_exe);

    const run_dis_exe = b.addRunArtifact(i8080dis_exe);
    if (b.args) |args|
        run_dis_exe.addArgs(args);

    b.step("run-dis", "run the disassmbler").dependOn(&run_dis_exe.step);

    const run_emu_exe = b.addRunArtifact(i8080emu_exe);
    if (b.args) |args|
        run_emu_exe.addArgs(args);

    b.step("run-emu", "run the emulator").dependOn(&run_emu_exe.step);

    const bios_src = "emulator/bios.S";
    const bios_bin = "emulator/bios.bin";

    const bios_build_run = b.addSystemCommand(&.{ "nasm", "-f", "bin", bios_src, "-o", bios_bin });
    const run_bios = b.addRunArtifact(i8080emu_exe);
    run_bios.step.dependOn(&bios_build_run.step);
    run_bios.addArg(bios_bin);
    b.step("run-bios", "run-bios").dependOn(&run_bios.step);

    const test_run = b.addTest(.{ .root_module = i8086_mod });
    b.step("test", "run unit tests").dependOn(&test_run.step);

    // const nasm_files: []const []const u8 = comptime &.{
    //     "tiny_test.S",
    //     "mov.S",
    //     "add.S",
    //     "and.S",
    //     "or.S",
    //     "helloworld.S",
    // };

    // const rom_test_step = b.step("rom-test", "run test roms");
    // inline for (nasm_files) |asm_name| {
    //     const asm_path = "asm_src/" ++ asm_name;
    //     const bin_path = asm_path ++ ".bin";
    //     const build_bin = b.addSystemCommand(&.{ "nasm", "-f", "bin", asm_path, "-o", bin_path });
    //     const run = b.addRunArtifact(i8080emu_exe);
    //     run.addArg(bin_path);
    //     run.step.dependOn(&build_bin.step);
    //     rom_test_step.dependOn(&run.step);
    // }
}

const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("zevem", Build.Module.CreateOptions{
        .root_source_file = b.path("src/evm.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addStaticLibrary(.{
        .name = "zevem",
        .root_source_file = b.path("src/evm.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const bin = b.addExecutable(.{
        .name = "zevem",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_cmd = b.addRunArtifact(bin);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Execute zevem");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests_cmd = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Unit test zevem");
    test_step.dependOn(&run_unit_tests_cmd.step);
}

// comptime {
//     const zig_ver_str = "0.14.0-dev.2851+b074fb7dd";
//     const supported_zig = std.SemanticVersion.parse(zig_ver_str) catch unreachable;
//     if (builtin.zig_version.order(supported_zig) != .eq) {
//         @compileError(std.fmt.comptimePrint("Unsupported Zig version {}; require {s}", .{ builtin.zig_version, zig_ver_str }));
//     }
// }

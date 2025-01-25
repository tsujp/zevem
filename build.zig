const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const run_step = b.step("run", "Do the thing");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests_cmd = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Test the thing");
    test_step.dependOn(&run_unit_tests_cmd.step);
}

comptime {
    const zig_ver_str = "0.14.0-dev.2851+b074fb7dd";
    const supported_zig = std.SemanticVersion.parse(zig_ver_str) catch unreachable;
    if (builtin.zig_version.order(supported_zig) != .eq) {
        @compileError(std.fmt.comptimePrint("Unsupported Zig version {}; require {s}", .{ builtin.zig_version, zig_ver_str }));
    }
}

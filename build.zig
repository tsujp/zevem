const std = @import("std");
const builtin = @import("builtin");

// TODO: Add git commit hash and project semver into package version when compiled.
// TODO: builtin.output_mode approach could be useful, something to look at when zevem is much further along. https://ziglang.org/documentation/0.14.0/std/#builtin.output_mode -- ghostty also takes that approach.

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const want_tracy = b.option(bool, "tracy", "Enable Tracy profiling") orelse false;
    const want_binary = b.option(bool, "with-cli", "Build zevem cli") orelse true;

    const test_filters = b.option([]const []const u8, "test-filter", "Skip tests which do not match any of the specified test filters") orelse &.{};

    // TODO: Add warning text if tracy is enabled that notes the performance impact (for people who might accidentally be doing so).

    const lib_mod = b.addModule("zevem", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addStaticLibrary(.{
        .name = "zevem",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    const lib_test = b.addTest(.{
        .root_module = lib_mod,
        .filters = test_filters,

        // TEMP: Custom test runner hacking.
        // .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
        // .test_runner = .{ .path = b.path("src/test_runner_2.zig"), .mode = .simple },
        // .test_runner = .{ .path = b.path("src/test_runner_3.zig"), .mode = .simple },
    });

    // Add lib_mod to itself (lib_mod) as an importable module called "zevem" so that in test files we can simply `@import("zevem")` instead of having to `@import("../../zevem.zig");` which would depend on the location of the test file in-question.
    lib_mod.addImport("zevem", lib_mod);

    const test_step = b.step("test", "Unit test zevem");
    const run_test_cmd = b.addRunArtifact(lib_test);
    test_step.dependOn(&run_test_cmd.step);

    const tracy = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
        .tracy_enable = want_tracy,
        .tracy_callstack = 10,
        .tracy_no_exit = false,
    });

    lib_mod.addImport("tracy", tracy.module("tracy"));

    if (want_tracy) {
        // lib_mod.addImport("tracy", tracy.module("tracy"));
        lib_mod.linkLibrary(tracy.artifact("tracy"));
    }

    if (want_binary) {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        exe_mod.addImport("zevem", lib_mod);

        const exe = b.addExecutable(.{
            .name = "zevem",
            .root_module = exe_mod,
        });

        exe_mod.addImport("tracy", tracy.module("tracy"));
        const run_interpreter = b.addRunArtifact(exe);
        const run_step = b.step("run", "Run the interpreter");
        run_step.dependOn(&run_interpreter.step);

        if (want_tracy) {
            // exe_mod.addImport("tracy", tracy.module("tracy"));
            exe_mod.linkLibrary(tracy.artifact("tracy"));
            // exe.linkLibCpp();
        }

        b.installArtifact(exe);
    }
}

// comptime {
//     const zig_ver_str = "0.14.0-dev.3028+cdc9d65b0";
//     const supported_zig = std.SemanticVersion.parse(zig_ver_str) catch unreachable;
//     if (builtin.zig_version.order(supported_zig) != .eq) {
//         @compileError(std.fmt.comptimePrint("Unsupported Zig version {}; require {s}", .{ builtin.zig_version, zig_ver_str }));
//     }
// }

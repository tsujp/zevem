const std = @import("std");
const builtin = @import("builtin");

// TODO: Options to build zevem as either a library for consumption versus its own standalone "tooling" mode which is the same but would have a slower interface by nature of not being embedded into a host program. Still unsure if normal b.addLibrary and so forth cover this or are "blanket" approaches. See addInstallArtifact which could be of use there.
// TODO: Add git commit hash and project semver into package version when compiled.
// TODO: builtin.output_mode approach could be useful, something to look at when zevem is much further along. https://ziglang.org/documentation/0.14.0/std/#builtin.output_mode -- ghostty also takes that approach.
// TODO: Ghostty build approach is rather complex, MIGHT be good inspiration if warranted in the future.
// TODO: "zevem" as a named import for tests to use instead of "../../zevem.zig"?

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const enable_tracy = b.option(bool, "tracy", "Enable Tracy profiling") orelse false;
    const want_binary = b.option(bool, "with-binary", "Also build zevem binary") orelse true;

    // TODO: I think createModule is correct here, addModule does the same but also adds the module to this package's module set so our dependents can access it but AFAIU that would be for dependencies _this_ package has that we want to allow our dependents (consumers) to also have access to (e.g. for config or whatever).
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/zevem.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_test = b.addTest(.{
        .root_module = lib_mod,
    });

    // Add lib_mod to itself (lib_mod) as an importable module called "zevem" so that in test files we can simply `@import("zevem")` instead of having to `@import("../../zevem.zig");` which would depend on the location of the test file in-question.
    lib_mod.addImport("zevem", lib_mod);

    const test_step = b.step("test", "Unit test zevem");
    const run_test_cmd = b.addRunArtifact(lib_test);
    test_step.dependOn(&run_test_cmd.step);

    if (want_binary) {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path("src/cli.zig"),
            .target = target,
            .optimize = optimize,
        });

        const exe = b.addExecutable(.{
            .name = "zevem",
            .root_module = exe_mod,
        });

        // Generate zevem cli binary.
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

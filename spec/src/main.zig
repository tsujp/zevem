//! Consume execution-spec-tests state test fixtures against zevem.
//!
//! Usage:
//!   zevem-spec [--fork=Cancun] [--max=N] [--strict] [--verbose] [--evm-trace] PATH...
//!
//! PATH is a fixture JSON file or a directory which is walked recursively.
//! See spec/README.org for the full story.

const std = @import("std");

const fixture = @import("fixture.zig");
const runner = @import("runner.zig");

const Options = struct {
    fork: []const u8 = "Cancun",
    max: ?usize = null,
    strict: bool = false,
    verbose: bool = false,
    evm_trace: bool = false,
    paths: []const []const u8 = &.{},
};

const Tally = struct {
    pass: usize = 0,
    pass_exception: usize = 0,
    fail: usize = 0,
    skip: std.EnumArray(runner.SkipReason, usize) = .initFill(0),
    parse_failures: usize = 0,

    fn executed(self: *const Tally) usize {
        var skipped: usize = 0;
        for (self.skip.values) |count| skipped += count;
        return self.pass + self.pass_exception + self.fail + skipped;
    }
};

const FailRecord = struct {
    case_name: []const u8,
    entry_index: usize,
    message: []const u8,
};

const MAX_FAIL_RECORDS = 20;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const options = parseArgs(args[1..]) catch {
        try usage();
        std.process.exit(2);
    };

    if (options.paths.len == 0) {
        try usage();
        std.process.exit(2);
    }

    // zevem's interpreter currently traces every executed opcode to stderr,
    // which is noise at fixture volume. Silence it unless asked not to.
    if (!options.evm_trace) try silenceStderr();

    // Holds anything that must survive the whole run (fail records).
    var run_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer run_arena.deinit();

    const files = try collectFixtureFiles(run_arena.allocator(), options.paths);

    var tally = Tally{};
    var fails = std.ArrayListUnmanaged(FailRecord).empty;

    // Per-file arena, reset between files to bound memory across thousands of
    // fixtures.
    var file_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer file_arena.deinit();

    const stdout = std.io.getStdOut().writer();

    files: for (files) |path| {
        _ = file_arena.reset(.retain_capacity);
        const file_alloc = file_arena.allocator();

        const bytes = std.fs.cwd().readFileAlloc(file_alloc, path, 1 << 30) catch |err| {
            try stdout.print("error: cannot read {s}: {s}\n", .{ path, @errorName(err) });
            tally.parse_failures += 1;
            continue;
        };

        const cases = fixture.parseSlice(file_alloc, bytes) catch |err| {
            try stdout.print("error: cannot parse {s}: {s}\n", .{ path, @errorName(err) });
            tally.parse_failures += 1;
            continue;
        };

        for (cases) |case| {
            var results = std.ArrayListUnmanaged(runner.EntryResult).empty;
            try runner.runCase(file_alloc, case, options.fork, &results);

            for (results.items) |result| {
                switch (result.outcome) {
                    .pass => tally.pass += 1,
                    .pass_exception => tally.pass_exception += 1,
                    .fail => |message| {
                        tally.fail += 1;
                        if (fails.items.len < MAX_FAIL_RECORDS) {
                            // Copy out of the per-file arena.
                            try fails.append(run_arena.allocator(), .{
                                .case_name = try run_arena.allocator().dupe(u8, result.case_name),
                                .entry_index = result.entry_index,
                                .message = try run_arena.allocator().dupe(u8, message),
                            });
                        }
                        if (options.verbose) {
                            try stdout.print("FAIL {s} [{d}]\n  {s}\n", .{ result.case_name, result.entry_index, message });
                        }
                    },
                    .skip => |reason| {
                        tally.skip.getPtr(reason).* += 1;
                        if (options.verbose and reason != .fork_filtered) {
                            try stdout.print("SKIP {s} [{d}]: {s}\n", .{ result.case_name, result.entry_index, reason.describe() });
                        }
                    },
                }

                if (options.max) |max| {
                    if (tally.executed() >= max) break :files;
                }
            }
        }
    }

    try printSummary(stdout, &tally, fails.items, options);

    if (options.strict and (tally.fail > 0 or tally.parse_failures > 0)) std.process.exit(1);
}

fn parseArgs(args: []const [:0]u8) !Options {
    var options = Options{};

    var paths = std.ArrayListUnmanaged([]const u8).empty;
    // Lives as long as the process; freed by OS at exit.
    const static_alloc = std.heap.page_allocator;

    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--fork=")) {
            options.fork = arg["--fork=".len..];
        } else if (std.mem.startsWith(u8, arg, "--max=")) {
            options.max = try std.fmt.parseInt(usize, arg["--max=".len..], 10);
        } else if (std.mem.eql(u8, arg, "--strict")) {
            options.strict = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--evm-trace")) {
            options.evm_trace = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownFlag;
        } else {
            try paths.append(static_alloc, arg);
        }
    }

    options.paths = paths.items;
    return options;
}

fn usage() !void {
    try std.io.getStdOut().writer().writeAll(
        \\usage: zevem-spec [--fork=Cancun] [--max=N] [--strict] [--verbose] [--evm-trace] PATH...
        \\
        \\Consumes execution-spec-tests state test fixtures (JSON files or
        \\directories of them) and reports zevem's conformance.
        \\
        \\  --fork=NAME   Run post entries for this fork only (default Cancun).
        \\  --max=N       Stop after N entries.
        \\  --strict      Exit non-zero if any entry fails (for CI).
        \\  --verbose     Print every failing and skipped entry as it happens.
        \\  --evm-trace   Keep zevem's per-opcode stderr tracing.
        \\
    );
}

/// Redirect stderr to /dev/null. POSIX targets only; a no-op elsewhere.
fn silenceStderr() !void {
    if (@import("builtin").os.tag == .windows) return;

    const null_fd = try std.posix.open("/dev/null", .{ .ACCMODE = .WRONLY }, 0);
    defer std.posix.close(null_fd);
    try std.posix.dup2(null_fd, std.posix.STDERR_FILENO);
}

/// Expand the given paths into a sorted list of fixture JSON files.
fn collectFixtureFiles(alloc: std.mem.Allocator, paths: []const []const u8) ![]const []const u8 {
    var files = std.ArrayListUnmanaged([]const u8).empty;

    for (paths) |path| {
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
            error.NotDir => {
                try files.append(alloc, try alloc.dupe(u8, path));
                continue;
            },
            else => return err,
        };
        defer dir.close();

        var walker = try dir.walk(alloc);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.basename, ".json")) continue;
            try files.append(alloc, try std.fs.path.join(alloc, &.{ path, entry.path }));
        }
    }

    std.mem.sort([]const u8, files.items, {}, pathLessThan);
    return files.items;
}

fn pathLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn printSummary(writer: anytype, tally: *const Tally, fails: []const FailRecord, options: Options) !void {
    try writer.print("\nzevem-spec: fork {s}\n", .{options.fork});
    try writer.print("{s}\n", .{"-" ** 72});

    const executed = tally.executed();
    try writer.print("entries:         {d}\n", .{executed});
    try writer.print("pass:            {d}\n", .{tally.pass});
    try writer.print("pass (rejected): {d}\n", .{tally.pass_exception});
    try writer.print("fail:            {d}\n", .{tally.fail});

    var skipped: usize = 0;
    for (tally.skip.values) |count| skipped += count;
    try writer.print("skip:            {d}\n", .{skipped});

    inline for (std.meta.fields(runner.SkipReason)) |field| {
        const reason: runner.SkipReason = @enumFromInt(field.value);
        const count = tally.skip.get(reason);
        if (count > 0) {
            try writer.print("  {s}: {d} ({s})\n", .{ field.name, count, reason.describe() });
        }
    }

    if (tally.parse_failures > 0) {
        try writer.print("unparseable files: {d}\n", .{tally.parse_failures});
    }

    if (fails.len > 0) {
        try writer.print("\nfirst {d} failures:\n", .{fails.len});
        for (fails) |record| {
            try writer.print("  {s} [{d}]\n", .{ record.case_name, record.entry_index });
            var lines = std.mem.splitScalar(u8, std.mem.trimRight(u8, record.message, "\n"), '\n');
            while (lines.next()) |line| try writer.print("    {s}\n", .{line});
        }
    }
}

test {
    _ = @import("rlp.zig");
    _ = @import("trie.zig");
    _ = @import("state.zig");
    _ = @import("fixture.zig");
    _ = @import("runner.zig");
    _ = @import("vendored_test.zig");
}

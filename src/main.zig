//! Command-line binary root.

const std = @import("std");
const print = std.debug.print;

const zevem = @import("zevem");
const EVM = zevem.EVM;

const config = zevem.config;
const tracy = if (config.use_tracy) @import("tracy") else struct {};

pub fn main() !void {
    const zone = if (config.use_tracy) tracy.initZone(@src(), .{ .name = "cli main" });
    defer if (config.use_tracy) zone.deinit();
    print("Hello, command-line world!\n", .{});

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var dummyEnv = zevem.DummyEnv{ .block = .default };
    var evm2 = try EVM.init(allocator, &dummyEnv);
    try evm2.execute(.{ .sender = 0, .gas = 100_000, .code = &.{ 0x5F, 0x60, 0x11, 0x61, 0x22, 0x33, 0x00 }, .data = "" });
    print("Done!", .{});
}

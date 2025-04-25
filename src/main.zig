//! Command-line binary root.

const std = @import("std");
const print = std.debug.print;

const zevem = @import("zevem");
const EVM = zevem.EVM;

const tracy = @import("tracy");

pub fn main() !void {
    const zone = tracy.initZone(@src(), .{ .name = "cli main" });
    defer zone.deinit();
    print("Hello, command-line world!\n", .{});

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var dummyEnv = zevem.DummyEnv{ .block = .default };
    var evm2 = try EVM.init(allocator, &dummyEnv);
    try evm2.execute(&.{ 0x5F, 0x60, 0x11, 0x61, 0x22, 0x33, 0x00 });
    print("Done!", .{});
}

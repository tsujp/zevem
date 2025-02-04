const std = @import("std");
const util = @import("util.zig");
const print = std.debug.print;
const EnumField = std.builtin.Type.EnumField;
const fmt = std.fmt;
const DummyEnv = util.DummyEnv;
const EVM = util.EVM;

pub fn main() !void {
    var dummyEnv = DummyEnv{};
    var evm2 = try EVM.init(&dummyEnv);
    try evm2.execute(&.{ 0x5F, 0x60, 0x11, 0x61, 0x22, 0x33, 0x00 });
}

const std = @import("std");
const print = std.debug.print;
const EnumField = std.builtin.Type.EnumField;
const fmt = std.fmt;

const EVM = @import("evm.zig").EVM;

pub fn main() !void {
    var evm2 = try EVM.init();
    try evm2.execute(&.{ 0x5F, 0x60, 0x11, 0x61, 0x22, 0x33, 0x00 });
}

const std = @import("std");
const print = std.debug.print;
const EnumField = std.builtin.Type.EnumField;

const EVM = @import("evm.zig").EVM;

pub fn main() !void {
    var evm = try EVM.init();

    // XXX: Garbage for now, will delete shortly.
    // TODO: Tests with real (for now) simple bytecode (non-context).
    try evm.execute(&.{ 0x01, 0x02, 0x00 });
}

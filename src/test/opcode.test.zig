// TODO: Better pattern here? Idk, you can take DRY too far.
const util = @import("../util.zig");
const basicBytecode = util.evmBasicBytecode;
const bc = util.htb;
const std = @import("std");

// TODO: Tests should assert stack size changes, and maybe also gas cost (for the basic ones).
// TODO: Assembler from some basic instruction format because long strings like this are shit.
test "basic ADD" {
    // Two plus two is faw!
    var a = try basicBytecode("600260020100");
    try std.testing.expect(a.stack.pop() == 4);

    // (2^256 - 1) + (2^256 - 1) = (2^256 - 2)
    var b = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0100");
    try std.testing.expect(b.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);
}

test "basic MUL" {
    var a = try basicBytecode("600660090200");
    try std.testing.expect(a.stack.pop() == 54);

    // (2^256 - 1) * (2^256 - 1) = 1
    var b = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0200");
    try std.testing.expect(b.stack.pop() == 1);
}

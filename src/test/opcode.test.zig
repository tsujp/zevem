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

test "basic SUB" {
    // Two plus two is faw minus one dats free QUICK MAFFS!
    var a = try basicBytecode("600160040300");
    try std.testing.expect(a.stack.pop() == 3);

    // Stack order is important, this is 1 - 4
    var b = try basicBytecode("600460010300");
    try std.testing.expect(b.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd);
}

test "basic DIV" {
    // Division by zero is zero.
    var a = try basicBytecode("600060010400");
    try std.testing.expect(a.stack.pop() == 0);

    // Division of zero is zero.
    var b = try basicBytecode("600160000400");
    try std.testing.expect(b.stack.pop() == 0);

    // Integer division: 10 / 3 = 3.
    var c = try basicBytecode("6003600a0400");
    try std.testing.expect(c.stack.pop() == 3);

    var d = try basicBytecode("60077fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0400");
    try std.testing.expect(d.stack.pop() == 0x2492492492492492492492492492492492492492492492492492492492492492);

    var e = try basicBytecode("60257fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeeee0400");
    try std.testing.expect(e.stack.pop() == 0x6eb3e45306eb3e45306eb3e45306eb3e45306eb3e45306eb3e45306eb3e44ba);
}

test "basic SDIV" {
    // Division by zero is zero.
    var a = try basicBytecode("600060010500");
    try std.testing.expect(a.stack.pop() == 0);

    // Division of zero is zero.
    var b = try basicBytecode("600160000500");
    try std.testing.expect(b.stack.pop() == 0);

    var c = try basicBytecode("60257fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeeee0500");
    try std.testing.expect(c.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8a);

    // TODO: Test truncation.
}

test "basic MOD" {
    // Modulus with 0 denominator = 0.
    var a = try basicBytecode("600060010600");
    try std.testing.expect(a.stack.pop() == 0);

    // 10 % 3 = 1.
    var b = try basicBytecode("6003600a0600");
    try std.testing.expect(b.stack.pop() == 1);

    var c = try basicBytecode("60037ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb0600");
    try std.testing.expect(c.stack.pop() == 2);
}

test "basic SMOD" {
    var a = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80700");
    try std.testing.expect(a.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);

    var b = try basicBytecode("60037ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb0700");
    try std.testing.expect(b.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);
}

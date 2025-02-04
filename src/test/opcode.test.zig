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

test "basic ADDMOD" {
    var a = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60047fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0800");
    try std.testing.expect(a.stack.pop() == 4);

    var b = try basicBytecode("600260027fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0800");
    try std.testing.expect(b.stack.pop() == 1);
}

test "basic MULMOD" {
    // (2^256 - 1) * (2^256 - 1) % 12 = 9
    var a = try basicBytecode("60127fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0900");
    try std.testing.expect(a.stack.pop() == 9);
}

test "basic EXP" {
    // ////////////////////// If exponent is 0 result := 1.
    // /////////////

    // 255^0
    var a01 = try basicBytecode("600060ff0a00");
    try std.testing.expect(a01.stack.pop() == 1);

    // 1^0
    var a02 = try basicBytecode("5f60010a00");
    try std.testing.expect(a02.stack.pop() == 1);

    var a03 = try basicBytecode("7f00000000000000000000000000000000000000000000000000000000000000007fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeee50a00");
    try std.testing.expect(a03.stack.pop() == 1);

    // ////////////////////// If base is 0 result := 0.
    // /////////////

    // 0^1
    var b01 = try basicBytecode("60015f0a00");
    try std.testing.expect(b01.stack.pop() == 0);

    var b02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60000a00");
    try std.testing.expect(b02.stack.pop() == 0);

    // ////////////////////// Except 0 raised to 0 which is defined := 1.
    // /////////////

    // 0^0 with push0
    var c01 = try basicBytecode("5f5f0a00");
    try std.testing.expect(c01.stack.pop() == 1);

    // 0^0 with explicit pushN
    var c02 = try basicBytecode("600060000a00");
    try std.testing.expect(c02.stack.pop() == 1);

    // ////////////////////// General.
    // /////////////

    var d01 = try basicBytecode("60ff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try std.testing.expect(d01.stack.pop() == 0);

    var d02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff0a00");
    try std.testing.expect(d02.stack.pop() == 0xc3c5ad91264cb4b9861fb06c007b72e6d1718ff9ad607fded1c19354df1ef714);

    var d03 = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try std.testing.expect(d03.stack.pop() == 0);

    var d04 = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff07fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try std.testing.expect(d04.stack.pop() == 0);

    var d05 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0a00");
    try std.testing.expect(d05.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);

    var d06 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeee50a00");
    try std.testing.expect(d06.stack.pop() == 0x14e59abaf9f01abbc8f816461dc19405a0de1e3d3a113421e694b2b7c4032d56);

    var d07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try std.testing.expect(d07.stack.pop() == 0);

    var d08 = try basicBytecode("7effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try std.testing.expect(d08.stack.pop() == 0x4fe63c7b38548808bcc441513969d99ad4a53a0c67bc73f8780b2d14cb2c4b7);

    var d09 = try basicBytecode("60cc60020a00");
    try std.testing.expect(d09.stack.pop() == 0x1000000000000000000000000000000000000000000000000000);
}

test "basic LT" {
    // 1 < 5 = 1
    var a01 = try basicBytecode("600560011000");
    try std.testing.expect(a01.stack.pop() == 1);

    // 0 < 1 = 1
    var a02 = try basicBytecode("60015f1000");
    try std.testing.expect(a02.stack.pop() == 1);

    // 0 < 0 = 0
    var a03 = try basicBytecode("5f5f1000");
    try std.testing.expect(a03.stack.pop() == 0);

    // 420 < 69 = 0
    var a04 = try basicBytecode("60456101a41000");
    try std.testing.expect(a04.stack.pop() == 0);
}

test "basic GT" {
    // 1 > 5 = 0
    var a01 = try basicBytecode("600560011100");
    try std.testing.expect(a01.stack.pop() == 0);

    // 0 > 1 = 0
    var a02 = try basicBytecode("60015f1100");
    try std.testing.expect(a02.stack.pop() == 0);

    // 0 > 0 = 0
    var a03 = try basicBytecode("5f5f1100");
    try std.testing.expect(a03.stack.pop() == 0);

    // 420 > 69 = 1
    var a04 = try basicBytecode("60456101a41100");
    try std.testing.expect(a04.stack.pop() == 1);
}

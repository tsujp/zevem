// TODO: Better pattern here? Idk, you can take DRY too far.
const util = @import("../util.zig");
const basicBytecode = util.evmBasicBytecode;
const bc = util.htb;
const std = @import("std");
const expect = std.testing.expect;

// TODO: Tests should assert stack size changes, and maybe also gas cost (for the basic ones).
// TODO: Assembler from some basic instruction format because long strings like this are shit.
test "basic ADD" {
    // Two plus two is faw!
    var a = try basicBytecode("600260020100");
    try expect(a.stack.pop() == 4);

    // (2^256 - 1) + (2^256 - 1) = (2^256 - 2)
    var b = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0100");
    try expect(b.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);
}

test "basic MUL" {
    var a = try basicBytecode("600660090200");
    try expect(a.stack.pop() == 54);

    // (2^256 - 1) * (2^256 - 1) = 1
    var b = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0200");
    try expect(b.stack.pop() == 1);
}

test "basic SUB" {
    // Two plus two is faw minus one dats free QUICK MAFFS!
    var a = try basicBytecode("600160040300");
    try expect(a.stack.pop() == 3);

    // Stack order is important, this is 1 - 4
    var b = try basicBytecode("600460010300");
    try expect(b.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd);
}

test "basic DIV" {
    // Division by zero is zero.
    var a = try basicBytecode("600060010400");
    try expect(a.stack.pop() == 0);

    // Division of zero is zero.
    var b = try basicBytecode("600160000400");
    try expect(b.stack.pop() == 0);

    // Integer division: 10 / 3 = 3.
    var c = try basicBytecode("6003600a0400");
    try expect(c.stack.pop() == 3);

    var d = try basicBytecode("60077fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0400");
    try expect(d.stack.pop() == 0x2492492492492492492492492492492492492492492492492492492492492492);

    var e = try basicBytecode("60257fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeeee0400");
    try expect(e.stack.pop() == 0x6eb3e45306eb3e45306eb3e45306eb3e45306eb3e45306eb3e45306eb3e44ba);
}

test "basic SDIV" {
    // Division by zero is zero.
    var a = try basicBytecode("600060010500");
    try expect(a.stack.pop() == 0);

    // Division of zero is zero.
    var b = try basicBytecode("600160000500");
    try expect(b.stack.pop() == 0);

    var c = try basicBytecode("60257fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeeee0500");
    try expect(c.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8a);

    // TODO: Test truncation.
}

test "basic MOD" {
    // Modulus with 0 denominator = 0.
    var a = try basicBytecode("600060010600");
    try expect(a.stack.pop() == 0);

    // 10 % 3 = 1.
    var b = try basicBytecode("6003600a0600");
    try expect(b.stack.pop() == 1);

    var c = try basicBytecode("60037ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb0600");
    try expect(c.stack.pop() == 2);
}

test "basic SMOD" {
    var a = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80700");
    try expect(a.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);

    var b = try basicBytecode("60037ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb0700");
    try expect(b.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);
}

test "basic ADDMOD" {
    var a = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60047fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0800");
    try expect(a.stack.pop() == 4);

    var b = try basicBytecode("600260027fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0800");
    try expect(b.stack.pop() == 1);
}

test "basic MULMOD" {
    // (2^256 - 1) * (2^256 - 1) % 12 = 9
    var a = try basicBytecode("60127fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0900");
    try expect(a.stack.pop() == 9);
}

test "basic EXP" {
    // ////////////////////// If exponent is 0 result := 1.
    // /////////////

    // 255^0
    var a01 = try basicBytecode("600060ff0a00");
    try expect(a01.stack.pop() == 1);

    // 1^0
    var a02 = try basicBytecode("5f60010a00");
    try expect(a02.stack.pop() == 1);

    var a03 = try basicBytecode("7f00000000000000000000000000000000000000000000000000000000000000007fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeee50a00");
    try expect(a03.stack.pop() == 1);

    // ////////////////////// If base is 0 result := 0.
    // /////////////

    // 0^1
    var b01 = try basicBytecode("60015f0a00");
    try expect(b01.stack.pop() == 0);

    var b02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60000a00");
    try expect(b02.stack.pop() == 0);

    // ////////////////////// Except 0 raised to 0 which is defined := 1.
    // /////////////

    // 0^0 with push0
    var c01 = try basicBytecode("5f5f0a00");
    try expect(c01.stack.pop() == 1);

    // 0^0 with explicit pushN
    var c02 = try basicBytecode("600060000a00");
    try expect(c02.stack.pop() == 1);

    // ////////////////////// General.
    // /////////////

    var d01 = try basicBytecode("60ff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try expect(d01.stack.pop() == 0);

    var d02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff0a00");
    try expect(d02.stack.pop() == 0xc3c5ad91264cb4b9861fb06c007b72e6d1718ff9ad607fded1c19354df1ef714);

    var d03 = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try expect(d03.stack.pop() == 0);

    var d04 = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff07fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try expect(d04.stack.pop() == 0);

    var d05 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0a00");
    try expect(d05.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);

    var d06 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeee50a00");
    try expect(d06.stack.pop() == 0x14e59abaf9f01abbc8f816461dc19405a0de1e3d3a113421e694b2b7c4032d56);

    var d07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try expect(d07.stack.pop() == 0);

    var d08 = try basicBytecode("7effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try expect(d08.stack.pop() == 0x4fe63c7b38548808bcc441513969d99ad4a53a0c67bc73f8780b2d14cb2c4b7);

    var d09 = try basicBytecode("60cc60020a00");
    try expect(d09.stack.pop() == 0x1000000000000000000000000000000000000000000000000000);
}

test "basic SIGNEXTEND" {
    // TODO:
}

test "basic LT" {
    // 1 < 5 = 1
    var a01 = try basicBytecode("600560011000");
    try expect(a01.stack.pop() == 1);

    // 0 < 1 = 1
    var a02 = try basicBytecode("60015f1000");
    try expect(a02.stack.pop() == 1);

    // 0 < 0 = 0
    var a03 = try basicBytecode("5f5f1000");
    try expect(a03.stack.pop() == 0);

    // 420 < 69 = 0
    var a04 = try basicBytecode("60456101a41000");
    try expect(a04.stack.pop() == 0);
}

test "basic GT" {
    // 1 > 5 = 0
    var a01 = try basicBytecode("600560011100");
    try expect(a01.stack.pop() == 0);

    // 0 > 1 = 0
    var a02 = try basicBytecode("60015f1100");
    try expect(a02.stack.pop() == 0);

    // 0 > 0 = 0
    var a03 = try basicBytecode("5f5f1100");
    try expect(a03.stack.pop() == 0);

    // 420 > 69 = 1
    var a04 = try basicBytecode("60456101a41100");
    try expect(a04.stack.pop() == 1);
}

test "basic SLT" {
    // -420 < +69 = 1
    var a01 = try basicBytecode("60456101a45f031200");
    try expect(a01.stack.pop() == 1);

    // -2 < -1 = 1
    var a02 = try basicBytecode("60015f0360025f031200");
    try expect(a02.stack.pop() == 1);

    // 0 < 0 = 0
    var a03 = try basicBytecode("5f5f1200");
    try expect(a03.stack.pop() == 0);

    // +9 < -6 = 0
    var a04 = try basicBytecode("60065f0360091200");
    try expect(a04.stack.pop() == 0);
}

test "basic SGT" {
    // -420 > +69 = 0
    var a01 = try basicBytecode("60456101a45f031300");
    try expect(a01.stack.pop() == 0);

    // -2 > -1 = 0
    var a02 = try basicBytecode("60015f0360025f031300");
    try expect(a02.stack.pop() == 0);

    // 0 > 0 = 0
    var a03 = try basicBytecode("5f5f1300");
    try expect(a03.stack.pop() == 0);

    // +9 > -6 = 1
    var a04 = try basicBytecode("60065f0360091300");
    try expect(a04.stack.pop() == 1);
}

test "basic EQ" {
    // 0 == 0 = 1
    var a01 = try basicBytecode("5f5f1400");
    try expect(a01.stack.pop() == 1);

    // 0 == 1 = 0
    var a02 = try basicBytecode("60015f1400");
    try expect(a02.stack.pop() == 0);

    // -420 == -420 = 1
    var a03 = try basicBytecode("6101a45f036101a45f031400");
    try expect(a03.stack.pop() == 1);

    // -10 == +10 = 0
    var a04 = try basicBytecode("60105f0360101400");
    try expect(a04.stack.pop() == 0);
}

test "basic ISZERO" {
    // 0 == 0 = 1
    var a01 = try basicBytecode("5f1500");
    try expect(a01.stack.pop() == 1);

    // 0 == 1 = 0
    var a02 = try basicBytecode("60011500");
    try expect(a02.stack.pop() == 0);

    // No such thing as -0 in two's complement; not that ISZERO interprets them as such.
    var a03 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1500");
    try expect(a03.stack.pop() == 0);
}

test "basic AND" {
    var a01 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1600");
    try expect(a01.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1600");
    try expect(a02.stack.pop() == 0);

    var a03 = try basicBytecode("615555600f1600");
    try expect(a03.stack.pop() == 5);
}

test "basic OR" {
    var a01 = try basicBytecode("615555600f1700");
    try expect(a01.stack.pop() == 0x555f);

    var a02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1700");
    try expect(a02.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
}

test "basic XOR" {
    var a01 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1800");
    try expect(a01.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1800");
    try expect(a02.stack.pop() == 0);

    var a03 = try basicBytecode("615555600f1800");
    try expect(a03.stack.pop() == 0x555a);
}

test "basic NOT" {
    // Push0, NOT, expect u256 of all 1s.
    var a01 = try basicBytecode("5f1900");
    try expect(a01.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a02 = try basicBytecode("600f1900");
    try expect(a02.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0);

    var a03 = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff01900");
    try expect(a03.stack.pop() == 0x0f);
}

test "basic BYTE" {
    // TODO:
}

test "basic SHL" {
    // Tests from: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-145.md#shl-shift-left

    var a01 = try basicBytecode("60015f1b00");
    try expect(a01.stack.pop() == 1);

    var a02 = try basicBytecode("600160011b00");
    try expect(a02.stack.pop() == 2);

    var a03 = try basicBytecode("600160ff1b00");
    try expect(a03.stack.pop() == 0x8000000000000000000000000000000000000000000000000000000000000000);

    var a04 = try basicBytecode("60016101001b00");
    try expect(a04.stack.pop() == 0);

    var a05 = try basicBytecode("60016101011b00");
    try expect(a05.stack.pop() == 0);

    var a06 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1b00");
    try expect(a06.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60011b00");
    try expect(a07.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);

    var a08 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff1b00");
    try expect(a08.stack.pop() == 0x8000000000000000000000000000000000000000000000000000000000000000);

    var a09 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6101001b00");
    try expect(a09.stack.pop() == 0);

    var a10 = try basicBytecode("5f60011b00");
    try expect(a10.stack.pop() == 0);

    var a11 = try basicBytecode("7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60011b00");
    try expect(a11.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);
}

test "basic SHR" {
    // Tests from: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-145.md#shr-logical-shift-right

    var a01 = try basicBytecode("60015f1c00");
    try expect(a01.stack.pop() == 1);

    var a02 = try basicBytecode("600160011c00");
    try expect(a02.stack.pop() == 0);

    var a03 = try basicBytecode("7f800000000000000000000000000000000000000000000000000000000000000060011c00");
    try expect(a03.stack.pop() == 0x4000000000000000000000000000000000000000000000000000000000000000);

    var a04 = try basicBytecode("7f800000000000000000000000000000000000000000000000000000000000000060ff1c00");
    try expect(a04.stack.pop() == 1);

    var a05 = try basicBytecode("7f80000000000000000000000000000000000000000000000000000000000000006101001c00");
    try expect(a05.stack.pop() == 0);

    var a06 = try basicBytecode("7f80000000000000000000000000000000000000000000000000000000000000006101011c00");
    try expect(a06.stack.pop() == 0);

    var a07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1c00");
    try expect(a07.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a08 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60011c00");
    try expect(a08.stack.pop() == 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a09 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff1c00");
    try expect(a09.stack.pop() == 1);

    var a10 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6101001c00");
    try expect(a10.stack.pop() == 0);

    var a11 = try basicBytecode("5f60011c00");
    try expect(a11.stack.pop() == 0);
}

test "basic SAR" {
    // TODO:
}

test "basic KECCAK256" {
    // TODO:
}

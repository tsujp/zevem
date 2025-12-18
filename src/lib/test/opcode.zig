//! Opcode execution testing.

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const zevem = @import("zevem");
const utils = zevem.utils;
const EVM = zevem.EVM;
const Exception = zevem.evm.Exception;
const DummyEnv = zevem.DummyEnv;

const test_utils = @import("test_utils");
const Sut = test_utils.Sut;
const basicBytecode = test_utils.evmBasicBytecode;
const tx = test_utils.tx;

// TODO: Tests should assert stack size changes, and maybe also gas cost (for the basic ones).
// TODO: Assembler from some basic instruction format because long strings like this are shit.
test "basic ADD" {
    // Two plus two is faw!
    var a = try basicBytecode("600260020100");
    try expectEqual(4, a.stack.pop());

    // (2^256 - 1) + (2^256 - 1) = (2^256 - 2)
    var b = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0100");
    try expectEqual(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, b.stack.pop());
}

test "basic MUL" {
    var a = try basicBytecode("600660090200");
    try expectEqual(54, a.stack.pop());

    // (2^256 - 1) * (2^256 - 1) = 1
    var b = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0200");
    try expectEqual(1, b.stack.pop());
}

test "basic SUB" {
    // Two plus two is faw minus one dats free QUICK MAFFS!
    var a = try basicBytecode("600160040300");
    try expectEqual(3, a.stack.pop());

    // Stack order is important, this is 1 - 4
    var b = try basicBytecode("600460010300");
    try expectEqual(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd, b.stack.pop());
}

test "basic DIV" {
    // Division by zero is zero.
    var a = try basicBytecode("600060010400");
    try expectEqual(0, a.stack.pop());

    // Division of zero is zero.
    var b = try basicBytecode("600160000400");
    try expectEqual(0, b.stack.pop());

    // Integer division: 10 / 3 = 3.
    var c = try basicBytecode("6003600a0400");
    try expectEqual(3, c.stack.pop());

    var d = try basicBytecode("60077fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0400");
    try expectEqual(0x2492492492492492492492492492492492492492492492492492492492492492, d.stack.pop());

    var e = try basicBytecode("60257fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeeee0400");
    try expectEqual(0x6eb3e45306eb3e45306eb3e45306eb3e45306eb3e45306eb3e45306eb3e44ba, e.stack.pop());
}

test "basic SDIV" {
    // Division by zero is zero.
    var a = try basicBytecode("600060010500");
    try expectEqual(0, a.stack.pop());

    // Division of zero is zero.
    var b = try basicBytecode("600160000500");
    try expectEqual(0, b.stack.pop());

    var c = try basicBytecode("60257fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeeee0500");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8a, c.stack.pop());

    // TODO: Test truncation.
}

test "basic MOD" {
    // Modulus with 0 denominator = 0.
    var a = try basicBytecode("600060010600");
    try expectEqual(0, a.stack.pop());

    // 10 % 3 = 1.
    var b = try basicBytecode("6003600a0600");
    try expectEqual(1, b.stack.pop());

    var c = try basicBytecode("60037ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb0600");
    try expectEqual(2, c.stack.pop());
}

test "basic SMOD" {
    var a = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80700");
    try expectEqual(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, a.stack.pop());

    var b = try basicBytecode("60037ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb0700");
    try expectEqual(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, b.stack.pop());
}

test "basic ADDMOD" {
    var a = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60047fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0800");
    try expectEqual(4, a.stack.pop());

    var b = try basicBytecode("600260027fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0800");
    try expectEqual(1, b.stack.pop());
}

test "basic MULMOD" {
    // (2^256 - 1) * (2^256 - 1) % 12 = 9
    var a = try basicBytecode("60127fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0900");
    try expectEqual(9, a.stack.pop());
}

test "basic EXP" {
    // ////////////////////// If exponent is 0 result := 1.
    // /////////////

    // 255^0
    var a01 = try basicBytecode("600060ff0a00");
    try expectEqual(1, a01.stack.pop());

    // 1^0
    var a02 = try basicBytecode("5f60010a00");
    try expectEqual(1, a02.stack.pop());

    var a03 = try basicBytecode("7f00000000000000000000000000000000000000000000000000000000000000007fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeee50a00");
    try expectEqual(1, a03.stack.pop());

    // ////////////////////// If base is 0 result := 0.
    // /////////////

    // 0^1
    var b01 = try basicBytecode("60015f0a00");
    try expectEqual(0, b01.stack.pop());

    var b02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60000a00");
    try expectEqual(0, b02.stack.pop());

    // ////////////////////// Except 0 raised to 0 which is defined := 1.
    // /////////////

    // 0^0 with push0
    var c01 = try basicBytecode("5f5f0a00");
    try expectEqual(1, c01.stack.pop());

    // 0^0 with explicit pushN
    var c02 = try basicBytecode("600060000a00");
    try expectEqual(1, c02.stack.pop());

    // ////////////////////// General.
    // /////////////

    var d01 = try basicBytecode("60ff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try expectEqual(0, d01.stack.pop());

    var d02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff0a00");
    try expectEqual(0xc3c5ad91264cb4b9861fb06c007b72e6d1718ff9ad607fded1c19354df1ef714, d02.stack.pop());

    var d03 = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try expectEqual(0, d03.stack.pop());

    var d04 = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff07fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try expectEqual(0, d04.stack.pop());

    var d05 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0a00");
    try expectEqual(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, d05.stack.pop());

    var d06 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeee50a00");
    try expectEqual(0x14e59abaf9f01abbc8f816461dc19405a0de1e3d3a113421e694b2b7c4032d56, d06.stack.pop());

    var d07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try expectEqual(0, d07.stack.pop());

    var d08 = try basicBytecode("7effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0a00");
    try expectEqual(0x4fe63c7b38548808bcc441513969d99ad4a53a0c67bc73f8780b2d14cb2c4b7, d08.stack.pop());

    var d09 = try basicBytecode("60cc60020a00");
    try expectEqual(0x1000000000000000000000000000000000000000000000000000, d09.stack.pop());
}

test "basic SIGNEXTEND" {
    // s[1] is 0xff is -1 in two's complement, s[0] is 0 because 0 + 1 = 1 byte which is the size of s[1]; s[1] is extended completely to fill the word size (256 bits) meaning in this case all 256 bits are set to 1.
    var a01 = try basicBytecode("60ff5f0b00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a01.stack.pop());

    // 0x7f is 127 in two's complement which isn't negative so nothing is done.
    var a02 = try basicBytecode("607f5f0b00");
    try expectEqual(0x7f, a02.stack.pop());

    var a03 = try basicBytecode("60fe5f0b00");
    try expectEqual(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, a03.stack.pop());

    var a04 = try basicBytecode("60b35f0b00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb3, a04.stack.pop());

    // Uh oh! You provided s[0] as 1 forgetting it needs to be provided as the byte size minus 1, now SIGNEXTEND will read 2 bytes, but the MSBs will be zeroed thus this won't be a two's complement negative and so nothing will happen! D'oh! Git gudder n00b!
    var a05 = try basicBytecode("60ff60010b00");
    try expectEqual(0xff, a05.stack.pop());

    // Some 32-bit two's complement negative.
    var a06 = try basicBytecode("63ad24465f60030b00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffad24465f, a06.stack.pop());

    // There's nothing to do with a value that's already full-width.
    var a07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff601f0b00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a07.stack.pop());

    // If s[0] is given too low the result is unclobbered by "missed" more-significant bits.
    var a08 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60010b00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a08.stack.pop());

    var a09 = try basicBytecode("7effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff601e0b00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a09.stack.pop());
}

test "basic LT" {
    // 1 < 5 = 1
    var a01 = try basicBytecode("600560011000");
    try expectEqual(1, a01.stack.pop());

    // 0 < 1 = 1
    var a02 = try basicBytecode("60015f1000");
    try expectEqual(1, a02.stack.pop());

    // 0 < 0 = 0
    var a03 = try basicBytecode("5f5f1000");
    try expectEqual(0, a03.stack.pop());

    // 420 < 69 = 0
    var a04 = try basicBytecode("60456101a41000");
    try expectEqual(0, a04.stack.pop());
}

test "basic GT" {
    // 1 > 5 = 0
    var a01 = try basicBytecode("600560011100");
    try expectEqual(0, a01.stack.pop());

    // 0 > 1 = 0
    var a02 = try basicBytecode("60015f1100");
    try expectEqual(0, a02.stack.pop());

    // 0 > 0 = 0
    var a03 = try basicBytecode("5f5f1100");
    try expectEqual(0, a03.stack.pop());

    // 420 > 69 = 1
    var a04 = try basicBytecode("60456101a41100");
    try expectEqual(1, a04.stack.pop());
}

test "basic SLT" {
    // -420 < +69 = 1
    var a01 = try basicBytecode("60456101a45f031200");
    try expectEqual(1, a01.stack.pop());

    // -2 < -1 = 1
    var a02 = try basicBytecode("60015f0360025f031200");
    try expectEqual(1, a02.stack.pop());

    // 0 < 0 = 0
    var a03 = try basicBytecode("5f5f1200");
    try expectEqual(0, a03.stack.pop());

    // +9 < -6 = 0
    var a04 = try basicBytecode("60065f0360091200");
    try expectEqual(0, a04.stack.pop());
}

test "basic SGT" {
    // -420 > +69 = 0
    var a01 = try basicBytecode("60456101a45f031300");
    try expectEqual(0, a01.stack.pop());

    // -2 > -1 = 0
    var a02 = try basicBytecode("60015f0360025f031300");
    try expectEqual(0, a02.stack.pop());

    // 0 > 0 = 0
    var a03 = try basicBytecode("5f5f1300");
    try expectEqual(0, a03.stack.pop());

    // +9 > -6 = 1
    var a04 = try basicBytecode("60065f0360091300");
    try expectEqual(1, a04.stack.pop());
}

test "basic EQ" {
    // 0 == 0 = 1
    var a01 = try basicBytecode("5f5f1400");
    try expectEqual(1, a01.stack.pop());

    // 0 == 1 = 0
    var a02 = try basicBytecode("60015f1400");
    try expectEqual(0, a02.stack.pop());

    // -420 == -420 = 1
    var a03 = try basicBytecode("6101a45f036101a45f031400");
    try expectEqual(1, a03.stack.pop());

    // -10 == +10 = 0
    var a04 = try basicBytecode("60105f0360101400");
    try expectEqual(0, a04.stack.pop());
}

test "basic ISZERO" {
    // 0 == 0 = 1
    var a01 = try basicBytecode("5f1500");
    try expectEqual(1, a01.stack.pop());

    // 0 == 1 = 0
    var a02 = try basicBytecode("60011500");
    try expectEqual(0, a02.stack.pop());

    // No such thing as -0 in two's complement; not that ISZERO interprets them as such.
    var a03 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1500");
    try expectEqual(0, a03.stack.pop());
}

test "basic AND" {
    var a01 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1600");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a01.stack.pop());

    var a02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1600");
    try expectEqual(0, a02.stack.pop());

    var a03 = try basicBytecode("615555600f1600");
    try expectEqual(5, a03.stack.pop());
}

test "basic OR" {
    var a01 = try basicBytecode("615555600f1700");
    try expectEqual(0x555f, a01.stack.pop());

    var a02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1700");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a02.stack.pop());
}

test "basic XOR" {
    var a01 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1800");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a01.stack.pop());

    var a02 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1800");
    try expectEqual(0, a02.stack.pop());

    var a03 = try basicBytecode("615555600f1800");
    try expectEqual(0x555a, a03.stack.pop());
}

test "basic NOT" {
    // Push0, NOT, expect u256 of all 1s.
    var a01 = try basicBytecode("5f1900");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a01.stack.pop());

    var a02 = try basicBytecode("600f1900");
    try expectEqual(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0, a02.stack.pop());

    var a03 = try basicBytecode("7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff01900");
    try expectEqual(0x0f, a03.stack.pop());
}

test "basic BYTE" {
    // Tests from: https://github.com/ethereum/go-ethereum/blob/e3d61e6db028c412f74bc4d4c7e117a9e29d0de0/core/vm/instructions_test.go#L132-L139

    var a01 = try basicBytecode("7fabcdef09080706050403020100000000000000000000000000000000000000005f1a00");
    try expectEqual(0xab, a01.stack.pop());

    var a02 = try basicBytecode("7fabcdef090807060504030201000000000000000000000000000000000000000060011a00");
    try expectEqual(0xcd, a02.stack.pop());

    var a03 = try basicBytecode("7f00cdef090807060504030201ffffffffffffffffffffffffffffffffffffffff5f1a00");
    try expectEqual(0, a03.stack.pop());

    var a04 = try basicBytecode("7f00cdef090807060504030201ffffffffffffffffffffffffffffffffffffffff60011a00");
    try expectEqual(0xcd, a04.stack.pop());

    var a05 = try basicBytecode("7f0000000000000000000000000000000000000000000000000000000000102030601f1a00");
    try expectEqual(0x30, a05.stack.pop());

    var a06 = try basicBytecode("7f0000000000000000000000000000000000000000000000000000000000102030601e1a00");
    try expectEqual(0x20, a06.stack.pop());

    var a07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60201a00");
    try expectEqual(0, a07.stack.pop());

    var a08 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff67ffffffffffffffff1a00");
    try expectEqual(0, a08.stack.pop());
}

test "basic SHL" {
    // Tests from: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-145.md#shl-shift-left

    var a01 = try basicBytecode("60015f1b00");
    try expectEqual(1, a01.stack.pop());

    var a02 = try basicBytecode("600160011b00");
    try expectEqual(2, a02.stack.pop());

    var a03 = try basicBytecode("600160ff1b00");
    try expectEqual(0x8000000000000000000000000000000000000000000000000000000000000000, a03.stack.pop());

    var a04 = try basicBytecode("60016101001b00");
    try expectEqual(0, a04.stack.pop());

    var a05 = try basicBytecode("60016101011b00");
    try expectEqual(0, a05.stack.pop());

    var a06 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1b00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a06.stack.pop());

    var a07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60011b00");
    try expectEqual(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, a07.stack.pop());

    var a08 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff1b00");
    try expectEqual(0x8000000000000000000000000000000000000000000000000000000000000000, a08.stack.pop());

    var a09 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6101001b00");
    try expectEqual(0, a09.stack.pop());

    var a10 = try basicBytecode("5f60011b00");
    try expectEqual(0, a10.stack.pop());

    var a11 = try basicBytecode("7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60011b00");
    try expectEqual(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, a11.stack.pop());
}

test "basic SHR" {
    // Tests from: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-145.md#shr-logical-shift-right

    var a01 = try basicBytecode("60015f1c00");
    try expectEqual(1, a01.stack.pop());

    var a02 = try basicBytecode("600160011c00");
    try expectEqual(0, a02.stack.pop());

    var a03 = try basicBytecode("7f800000000000000000000000000000000000000000000000000000000000000060011c00");
    try expectEqual(0x4000000000000000000000000000000000000000000000000000000000000000, a03.stack.pop());

    var a04 = try basicBytecode("7f800000000000000000000000000000000000000000000000000000000000000060ff1c00");
    try expectEqual(1, a04.stack.pop());

    var a05 = try basicBytecode("7f80000000000000000000000000000000000000000000000000000000000000006101001c00");
    try expectEqual(0, a05.stack.pop());

    var a06 = try basicBytecode("7f80000000000000000000000000000000000000000000000000000000000000006101011c00");
    try expectEqual(0, a06.stack.pop());

    var a07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1c00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a07.stack.pop());

    var a08 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60011c00");
    try expectEqual(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a08.stack.pop());

    var a09 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff1c00");
    try expectEqual(1, a09.stack.pop());

    var a10 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6101001c00");
    try expectEqual(0, a10.stack.pop());

    var a11 = try basicBytecode("5f60011c00");
    try expectEqual(0, a11.stack.pop());
}

test "basic SAR" {
    // Tests from: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-145.md#sar-arithmetic-shift-right

    var a01 = try basicBytecode("60015f1d00");
    try expectEqual(1, a01.stack.pop());

    var a02 = try basicBytecode("600160011d00");
    try expectEqual(0, a02.stack.pop());

    var a03 = try basicBytecode("7f800000000000000000000000000000000000000000000000000000000000000060011d00");
    try expectEqual(0xc000000000000000000000000000000000000000000000000000000000000000, a03.stack.pop());

    var a04 = try basicBytecode("7f800000000000000000000000000000000000000000000000000000000000000060ff1d00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a04.stack.pop());

    var a05 = try basicBytecode("7f80000000000000000000000000000000000000000000000000000000000000006101001d00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a05.stack.pop());

    var a06 = try basicBytecode("7f80000000000000000000000000000000000000000000000000000000000000006101011d00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a06.stack.pop());

    var a07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1d00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a07.stack.pop());

    var a08 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60011d00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a08.stack.pop());

    var a09 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff1d00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a09.stack.pop());

    var a10 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6101001d00");
    try expectEqual(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, a10.stack.pop());

    var a11 = try basicBytecode("5f60011d00");
    try expectEqual(0, a11.stack.pop());

    var a12 = try basicBytecode("7f400000000000000000000000000000000000000000000000000000000000000060fe1d00");
    try expectEqual(1, a12.stack.pop());

    var a13 = try basicBytecode("7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60f81d00");
    try expectEqual(0x7f, a13.stack.pop());

    var a14 = try basicBytecode("7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60fe1d00");
    try expectEqual(1, a14.stack.pop());

    var a15 = try basicBytecode("7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff1d00");
    try expectEqual(0, a15.stack.pop());

    var a16 = try basicBytecode("7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6101001d00");
    try expectEqual(0, a16.stack.pop());
}

test "basic KECCAK256" {
    // TODO: Gas test.

    // Hash over the bytes "cafebabe", no offset.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        // Manually set memory contents and size.
        try sut.evm.mem.resize(sut.evm.alloc, 32);
        std.mem.writeInt(u256, @ptrCast(sut.evm.mem.items[0..32]), 0xcafebabe << 224, .big);
        printMemory(sut.evm.mem);

        // We've manually set memory so we only need to push the offset, and length then call
        //   the KECCAK256 opcode.
        const res = sut.executeBasic("60045f2000");
        try expectEqual({}, res);
        try expectEqual(1, sut.evm.stack.len);
        try expectEqual(32, sut.evm.mem.items.len); // Smallest possible memory size.

        try std.testing.expectEqualSlices(
            u8,
            &utils.htb("6fe2683bd1d27cbb7a05c570693bea39e0c082ed16722e5ecadcfb7cfdbd20db"),
            &wordAsBytes(sut.evm.stack.pop().?),
            // &@as([32]u8, @bitCast(sut.evm.stack.pop().?)),
        );
    }

    // Hash over empty input bytes as offset and length are both zero.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        // Manually set memory contents and size.
        try sut.evm.mem.resize(sut.evm.alloc, 32);
        std.mem.writeInt(u256, @ptrCast(sut.evm.mem.items[0..32]), 0, .big);
        printMemory(sut.evm.mem);

        // We've manually set memory so we only need to push the offset, and length then call
        //   the KECCAK256 opcode.
        const res = sut.executeBasic("5f5f2000");
        try expectEqual({}, res);
        try expectEqual(1, sut.evm.stack.len);
        try expectEqual(32, sut.evm.mem.items.len); // Smallest possible memory size.

        try std.testing.expectEqualSlices(
            u8,
            &utils.htb("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"),
            &wordAsBytes(sut.evm.stack.pop().?),
        );
    }

    // Hash over bytes that result in a memory resize, and use MSTORE to set up initial memory.
    // Hash: cafebabe00000000000000000000000000000000000000000000000000000000
    // Digest: 19b37ef47ae8e61211537fd93aa507187945b974da325ba02f7864dea756920c
    var a = try basicBytecode("63cafebabe6000526020601c20");
    printMemory(a.mem);
    try expectEqual(1, a.stack.len);
    try expectEqual(64, a.mem.items.len); // Memory resized to 2 words, or 64-bytes.
    try std.testing.expectEqualSlices(
        u8,
        &utils.htb("19b37ef47ae8e61211537fd93aa507187945b974da325ba02f7864dea756920c"),
        &wordAsBytes(a.stack.pop().?),
    );
}

test "basic ADDRESS" {
    // TODO: Test scenario, nested contexts.
    return error.SkipZigTest;
}

test "basic BALANCE" {
    // TODO
    return error.SkipZigTest;
}

// TODO: Change blockheader things back to functions and so update this test accordingly.
// test "basic NUMBER" {
//     const dummy_default = try basicBytecode("4300");
//     try std.testing.expectEqualSlices(u256, &[_]u256{0}, dummy_default.stack.constSlice());

//     // Expect a specific value from the environment.
//     var dummyEnv: DummyEnv = .default;
//     dummyEnv.block.number = 1234;

//     var gpa: std.heap.DebugAllocator(.{}) = .init;
//     const allocator = gpa.allocator();
//     var evm = try EVM.init(allocator, &dummyEnv);
//     const res = try evm.execute(&util.htb("4300"));
//     try expectEqual({}, res); // No error.
//     try std.testing.expectEqualSlices(u256, &[_]u256{1234}, evm.stack.constSlice());
// }

test "basic ORIGIN" {
    // TODO: Gas test.
    // TODO: Compliated test scenario, probably nested execution with contract creation to ensure
    //       it reports original transaction sender address only.

    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        _ = try sut.evm.execute(tx(.{
            .sender = 0x1234,
            .target = 0,
            .value = 0,
            .gas = 100_000,
            .gas_price = 0,
            .code = "3200",
            .data = "",
        }));

        try expectEqual(0x1234, sut.evm.stack.pop());
    }
}

test "basic CALLER" {
    // TODO: Need a test scenario, including with nested context. Need to actually derive the caller address or do we expect the user to be that before.
    return error.SkipZigTest;
}

test "basic CALLVALUE" {
    // TODO: Need a test scenario, including nested calls e.g. CALL/CREATE.
    return error.SkipZigTest;
}

test "basic CALLDATALOAD" {
    // TODO
    return error.SkipZigTest;
}

test "basic CALLDATASIZE" {
    // TODO: Need a test scenario, including nested context.
    return error.SkipZigTest;
}

test "basic CALLDATACOPY" {
    // TODO
    return error.SkipZigTest;
}

test "basic CODESIZE" {
    // TODO: Need a test scenario, but as zevem stands it's the users job to set Transaction.code correctly.
    return error.SkipZigTest;
}

test "basic CODECOPY" {
    // TODO
    return error.SkipZigTest;
}

test "basic GASPRICE" {
    // TODO: Need a test scenario, including nested context.
    return error.SkipZigTest;
}

test "basic EXTCODESIZE" {
    // TODO
    return error.SkipZigTest;
}

test "basic EXTCODECOPY" {
    // TODO
    return error.SkipZigTest;
}

test "basic RETURNDATASIZE" {
    // TODO
    return error.SkipZigTest;
}

test "basic RETURNDATACOPY" {
    // TODO
    return error.SkipZigTest;
}
test "basic EXTCODEHASH" {
    // TODO
    return error.SkipZigTest;
}

test "basic BLOCKHASH" {
    // TODO
    return error.SkipZigTest;
}

test "basic COINBASE" {
    // TODO
    return error.SkipZigTest;
}

test "basic TIMESTAMP" {
    // TODO
    return error.SkipZigTest;
}

test "basic NUMBER" {
    // TODO
    return error.SkipZigTest;
}

test "basic PREVRANDAO" {
    // TODO
    return error.SkipZigTest;
}

test "basic GASLIMIT" {
    // TODO
    return error.SkipZigTest;
}

test "basic CHAINID" {
    // TODO: Simpler test like with the basic block headers.
    return error.SkipZigTest;
}

test "basic SELFBALANCE" {
    // TODO: Test scenario, including nested contexts.
    return error.SkipZigTest;
}

test "basic BASEFEE" {
    // TODO
    return error.SkipZigTest;
}

test "basic BLOBHASH" {
    // TODO
    return error.SkipZigTest;
}

test "basic BLOBBASEFEE" {
    // TODO
    return error.SkipZigTest;
}

test "basic POP" {
    // Push 2 items, pop twice for great success!
    const a = try basicBytecode("600161cafe505000");
    try expectEqual(0, a.stack.len);

    // Push 2 items, pop one leaving the first-pushed item at the top.
    var b = try basicBytecode("61cafe61babe5000");
    try expectEqual(1, b.stack.len);
    try expectEqual(0xcafe, b.stack.pop());

    // TODO: Here and for many others do we want custom error types per opcode to test failing cases like this?
    // Push 2 items, but then try and pop 3 times.
    // const c = basicBytecode("5f600150505000");
    // try expect(c == error.Pop);
}

// TODO: Put elsewhere, fine here (for now).
// TODO: Header row offsets also, currently only full word offsets at the start of each row.
fn printMemory(mem: std.ArrayListUnmanaged(u8)) void {
    const print = std.debug.print;

    print("[MEMORY DUMP]\nwords={d}  bytes={d}\n", .{ mem.items.len / 32, mem.items.len });

    var it = std.mem.window(u8, mem.items, 32, 32);
    while (it.next()) |word| {
        const addr = (it.index orelse mem.items.len) - it.size;
        print("{x:0>6}:{d:<3}  ", .{ addr, addr });

        for (word, 0..) |byte, i| {
            print(" {x:0>2}", .{byte});
            if (@mod(i, 8) == 7) print(" ", .{});
        }

        print("\n", .{});
    }
}

test "basic MLOAD" {
    // TODO: Gas test.

    // Simple load without "weird" offset, and no memory resizing.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        // Manually set memory contents and (correct) memory size.
        try sut.evm.mem.resize(sut.evm.alloc, 32);
        std.mem.writeInt(u256, @ptrCast(sut.evm.mem.items[0..32]), 0xcafe, .big);
        printMemory(sut.evm.mem);

        // MLOAD from offset 0, effectively reading back the same value we set.
        const res = sut.executeBasic("5f5100");
        try expectEqual({}, res);
        try expectEqual(1, sut.evm.stack.len);
        try expectEqual(0xcafe, sut.evm.stack.pop());
        try expectEqual(32, sut.evm.mem.items.len); // No memory resizing.
    }

    // Simple load with a small offset, so memory will be resized and the value read back different.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        // Manually set memory contents and (correct) memory size.
        try sut.evm.mem.resize(sut.evm.alloc, 32);
        std.mem.writeInt(u256, @ptrCast(sut.evm.mem.items[0..32]), 0xcafe, .big);
        printMemory(sut.evm.mem);

        // MLOAD from offset 2 (bytes), effectively adding 2 bytes to the end of our initial value.
        const res = sut.executeBasic("60025100");
        try expectEqual({}, res);
        try expectEqual(1, sut.evm.stack.len);
        try expectEqual(0xcafe0000, sut.evm.stack.pop());
        try expectEqual(64, sut.evm.mem.items.len); // Small offset, so incremented one word (32 bytes).
        printMemory(sut.evm.mem);
    }

    // Simple load with large offset, large words, and no memory resizing.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        // Manually set memory contents and (correct) memory size.
        try sut.evm.mem.resize(sut.evm.alloc, 64);
        std.mem.writeInt(u256, @ptrCast(sut.evm.mem.items[0..32]), 90000, .big);
        std.mem.writeInt(u256, @ptrCast(sut.evm.mem.items[32..64]), 0x00cafebabe001234567800101000ffabc00222200666600333300001111fcafe, .big);
        printMemory(sut.evm.mem);

        // MLOAD from offset 30 (i.e. the 31st byte).
        const res = sut.executeBasic("601e5100");
        try expectEqual({}, res);
        try expectEqual(1, sut.evm.stack.len);
        try expectEqual(0x5f9000cafebabe001234567800101000ffabc00222200666600333300001111f, sut.evm.stack.pop());
        try expectEqual(64, sut.evm.mem.items.len); // Memory not resized.
        printMemory(sut.evm.mem);
    }

    // TODO: Test memory resizing relating to MLOAD.
}

test "basic MSTORE" {
    // TODO: Gas test.

    // Store 0xff..ff at 0xff, expanding the memory size in the process.
    const vm1 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff5200");
    try expectEqual(0, vm1.stack.len);
    printMemory(vm1.mem);
    try expectEqual(256 + 32, vm1.mem.items.len);
    for (0..0xff) |i| {
        try expectEqual(0, vm1.mem.items[i]);
    }
    for (0xff..0xff + 32) |i| {
        try expectEqual(0xff, vm1.mem.items[i]);
    }

    // Swap the two arguments, to check if an overflow is detected
    const overflow_result = basicBytecode("60ff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5200");
    try expectError(error.MemResizeUInt256Overflow, overflow_result);

    // TODO: Do we want to re-enable this test and have a test configuration where the EVM is allowed infinite gas? As it stands the (modified) sut form of this test passes u64 maximum gas and we can see it correctly reports out of gas since the gas limit would hit before a ludicrous memory size change.
    // Check the temporary condition that resizing the memory to an
    // incredible value is going to fail.
    // const resize_error = basicBytecode("60ff7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0005200");
    // try expectError(error.OutOfMemory, resize_error);
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        const res = sut.evm.execute(tx(.{
            .sender = 0,
            .target = 0,
            .value = 0,
            .gas = 18446744073709551615,
            .gas_price = 0,
            .code = "60ff7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0005200",
            .data = "",
        }));

        // try expectError(Exception.OutOfMemory, res); // TODO
        try expectError(Exception.OutOfGas, res);
    }

    // Check overwritten memory is correctly zeroed.
    // From: https://github.com/ethereum/go-ethereum/blob/32c6aa8a1a2595cbb89b05f93440d230841f8431/core/vm/instructions_test.go#L520
    const overwrites = try basicBytecode("7fabcdef00000000000000abba000000000deaf000000c0de001000000001337005f5260015f5200");
    printMemory(overwrites.mem);
    try expectEqual(0, overwrites.stack.len);
    try expectEqual(32, overwrites.mem.items.len);
    try expectEqual(1, std.mem.readInt(u256, overwrites.mem.items[0..32], .big));
}

test "basic MSTORE8" {
    // TODO: Gas test.

    // Both arguments to MSTORE8 are zero.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        const res = sut.executeBasic("5f5f5300");
        try expectEqual({}, res);
        try expectEqual(0, sut.evm.stack.len);
        try expectEqual(32, sut.evm.mem.items.len); // Smallest possible memory size.
        for (0..32) |i| {
            try expectEqual(0, sut.evm.mem.items[i]); // All memory items are zero.
        }
        printMemory(sut.evm.mem);
    }

    // Offset zero, with an already byte-sized value.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        const res = sut.executeBasic("60ff5f5300");
        try expectEqual({}, res);
        try expectEqual(0, sut.evm.stack.len);
        try expectEqual(32, sut.evm.mem.items.len); // Smallest possible memory size.
        try expectEqual(0xff, sut.evm.mem.items[0]); // Index 0 is 0xff.
        for (1..32) |i| {
            try expectEqual(0, sut.evm.mem.items[i]); // Remaining memory items are zero.
        }
        printMemory(sut.evm.mem);
    }

    // Offset 14, with a 4-byte value (which will undergo modulo 256).
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        const res = sut.executeBasic("63cafebabe600e5300");
        try expectEqual({}, res);
        try expectEqual(0, sut.evm.stack.len);
        try expectEqual(32, sut.evm.mem.items.len); // Smallest possible memory size.
        for (0..13) |i| {
            try expectEqual(0, sut.evm.mem.items[i]); // Indices 0 to 13 are zeroed.
        }
        // At index 14 is our 1-byte 256 modulo value which for 0xcafebabe is 190 decimal.
        try expectEqual(190, sut.evm.mem.items[14]);
        for (15..32) |i| {
            try expectEqual(0, sut.evm.mem.items[i]); // Remaining memory items are zero.
        }
        printMemory(sut.evm.mem);
    }
}

test "basic JUMP" {
    // JUMP jumps over INVALID opcode.
    var a01 = try basicBytecode("600556fefe5b5800");
    try expectEqual(6, a01.stack.pop());
}

test "basic JUMPI" {
    // False JUMPI condition (correctly) fails to jump over INVALID opcode, showing that a
    //   false condition simply increments the PC by 1.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        const res = sut.executeBasic("6000600757fefe5b5800");
        try expectError(Exception.InvalidOp, res);
    }

    // True JUMPI condition jumps over INVALID opcode.
    var a02 = try basicBytecode("6001600757fefe5b5800");
    try expectEqual(8, a02.stack.pop());
}

test "basic PC" {
    var a01 = try basicBytecode("5800");
    try expectEqual(0, a01.stack.pop());

    var a02 = try basicBytecode("585800");
    try expectEqual(1, a02.stack.pop());

    var b01 = try basicBytecode("63010203045800");
    try expectEqual(5, b01.stack.pop());

    var c01 = try basicBytecode("630000000856fefe5b5800");
    try expectEqual(9, c01.stack.pop());
}

test "basic MSIZE" {
    // TODO: Gas tests.
    // TODO: More complicated tests?

    // Nothing but MSIZE opcode, no addressed memory at all, should be zero.
    var a01 = try basicBytecode("5900");
    try expectEqual(0, a01.stack.pop());
    try expectEqual(0, a01.mem.items.len);

    // MSTORE some data such that memory should be 2 words, or 64-bytes.
    var a02 = try basicBytecode("63cafebabe6020525900");
    printMemory(a02.mem);
    try expectEqual(64, a02.stack.pop());
    try expectEqual(64, a02.mem.items.len);
}

test "basic GAS" {
    // Just the GAS opcode.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        _ = try sut.evm.execute(tx(.{
            .sender = 0,
            .target = 0,
            .value = 0,
            .gas = 100_000,
            .gas_price = 0,
            .code = "5a00",
            .data = "",
        }));

        try expectEqual(sut.evm.gas, sut.evm.stack.pop());
    }

    // An ADD before GAS, and an ADD followed by POP afterwards leaving GAS' prior value at the
    //   top of the stack (and we used gas afterwards).
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        _ = try sut.evm.execute(tx(.{
            .sender = 0,
            .target = 0,
            .value = 0,
            .gas = 100_000,
            .gas_price = 0,
            .code = "60026004015a600860160150",
            .data = "",
        }));

        // TODO: Use the enum for the pricing i.e. verylow, low etc.

        // At current pricing PUSH1, PUSH1, and ADD (called before GAS) amount to: 3 + 3 + 3 = 9
        //   as well as GAS' cost of 2 = 11 less than the provided gas limit, and G_transaction.
        try expectEqual(100_000 - 21_000 - 11, sut.evm.stack.pop());

        // And the final gas consumed will be 22.
        try expectEqual(100_000 - 21_000 - 22, sut.evm.gas);
    }
}

// JUMP, JUMPI, and JUMPDEST are co-dependent but we'll attempt to atomically test (as best we
//   can) anyway.
test "basic JUMPDEST" {
    // Simple JUMPDEST at 0x05 in bytecode, prefixed in INVALID. So, jumping will only be valid
    //   if we PUSH the correct offset (0x05) and that address is populated with JUMPDEST.
    var a01 = try basicBytecode("600556fefe5b601000");
    try expectEqual(16, a01.stack.pop());

    // PUSH 0x06 and attempt to JUMP. Except, while that address is populated with a JUMPDEST
    //   it's actually the data portion of the subsequent PUSH8 and so not valid.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        const res = sut.executeBasic("600656675b5b5b5b5b5b5b5b00");
        try expectError(Exception.InvalidJumpDestination, res);
    }

    // JUMPI whose condition is false (and so won't set the new program counter) can have a program
    //   counter value which points to a non-JUMPDEST because it's never set, and so is not an
    //   error.
    var b01 = try basicBytecode("6000600857635b5b5b5b00");
    try expectEqual(0x5b5b5b5b, b01.stack.pop());

    // If we do the same as before but set the JUMPI condition to true, and attempt to jump to an
    //   invalid JUMPDEST it should now error.
    {
        var sut: Sut = try .init(.{});
        defer sut.deinit();

        const res = sut.executeBasic("6001600857635b5b5b5b00");
        try expectError(Exception.InvalidJumpDestination, res);
    }
}

// TODO: Add super, super basic tests for PUSH0 .. PUSH32. Basically just one scenario per PUSHN because they are used in essentially every other test.

test "basic DUP" {
    // DUP1
    var d01_a = try basicBytecode("5f8000");
    try expectEqual(0, d01_a.stack.pop());

    var d01_b = try basicBytecode("5f60018000");
    try expectEqual(1, d01_b.stack.pop());

    var d01_c = try basicBytecode("5f80808000");
    try expectEqual(4, d01_c.stack.len);
    try expectEqual(0, d01_c.stack.pop());

    // DUP2
    var d02_a = try basicBytecode("60025f8100");
    try expectEqual(2, d02_a.stack.pop());

    var d02_b = try basicBytecode("5f60025f8100");
    try expectEqual(2, d02_b.stack.pop());

    // DUP3
    var d03_a = try basicBytecode("600c600a5f8200");
    try expectEqual(0xc, d03_a.stack.pop());

    // TODO: Generate the rest of these tests via a build-time script (or separate shell script).

    // DUP4
    // DUP5
    // DUP6
    // DUP7
    // DUP8
    // DUP9
    // DUP10
    // DUP11
    // DUP12
    // DUP13
    // DUP14
    // DUP15
    // DUP16
}

test "basic SWAP" {
    // Test cases generated by gen_swap_test.sh

    // SWAP1
    var s01_a = try basicBytecode("600660099000");
    try expectEqual(2, s01_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s01_a, 0));
    try expectEqual(9, utils.stackOffTop(&s01_a, 1));

    // SWAP2
    var s02_a = try basicBytecode("60065f60099100");
    try expectEqual(3, s02_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s02_a, 0));
    try expectEqual(9, utils.stackOffTop(&s02_a, 2));

    // SWAP3
    var s03_a = try basicBytecode("60065f5f60099200");
    try expectEqual(4, s03_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s03_a, 0));
    try expectEqual(9, utils.stackOffTop(&s03_a, 3));

    // SWAP4
    var s04_a = try basicBytecode("60065f5f5f60099300");
    try expectEqual(5, s04_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s04_a, 0));
    try expectEqual(9, utils.stackOffTop(&s04_a, 4));

    // SWAP5
    var s05_a = try basicBytecode("60065f5f5f5f60099400");
    try expectEqual(6, s05_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s05_a, 0));
    try expectEqual(9, utils.stackOffTop(&s05_a, 5));

    // SWAP6
    var s06_a = try basicBytecode("60065f5f5f5f5f60099500");
    try expectEqual(7, s06_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s06_a, 0));
    try expectEqual(9, utils.stackOffTop(&s06_a, 6));

    // SWAP7
    var s07_a = try basicBytecode("60065f5f5f5f5f5f60099600");
    try expectEqual(8, s07_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s07_a, 0));
    try expectEqual(9, utils.stackOffTop(&s07_a, 7));

    // SWAP8
    var s08_a = try basicBytecode("60065f5f5f5f5f5f5f60099700");
    try expectEqual(9, s08_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s08_a, 0));
    try expectEqual(9, utils.stackOffTop(&s08_a, 8));

    // SWAP9
    var s09_a = try basicBytecode("60065f5f5f5f5f5f5f5f60099800");
    try expectEqual(10, s09_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s09_a, 0));
    try expectEqual(9, utils.stackOffTop(&s09_a, 9));

    // SWAP10
    var s10_a = try basicBytecode("60065f5f5f5f5f5f5f5f5f60099900");
    try expectEqual(11, s10_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s10_a, 0));
    try expectEqual(9, utils.stackOffTop(&s10_a, 10));

    // SWAP11
    var s11_a = try basicBytecode("60065f5f5f5f5f5f5f5f5f5f60099a00");
    try expectEqual(12, s11_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s11_a, 0));
    try expectEqual(9, utils.stackOffTop(&s11_a, 11));

    // SWAP12
    var s12_a = try basicBytecode("60065f5f5f5f5f5f5f5f5f5f5f60099b00");
    try expectEqual(13, s12_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s12_a, 0));
    try expectEqual(9, utils.stackOffTop(&s12_a, 12));

    // SWAP13
    var s13_a = try basicBytecode("60065f5f5f5f5f5f5f5f5f5f5f5f60099c00");
    try expectEqual(14, s13_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s13_a, 0));
    try expectEqual(9, utils.stackOffTop(&s13_a, 13));

    // SWAP14
    var s14_a = try basicBytecode("60065f5f5f5f5f5f5f5f5f5f5f5f5f60099d00");
    try expectEqual(15, s14_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s14_a, 0));
    try expectEqual(9, utils.stackOffTop(&s14_a, 14));

    // SWAP15
    var s15_a = try basicBytecode("60065f5f5f5f5f5f5f5f5f5f5f5f5f5f60099e00");
    try expectEqual(16, s15_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s15_a, 0));
    try expectEqual(9, utils.stackOffTop(&s15_a, 15));

    // SWAP16
    var s16_a = try basicBytecode("60065f5f5f5f5f5f5f5f5f5f5f5f5f5f5f60099f00");
    try expectEqual(17, s16_a.stack.len);
    try expectEqual(6, utils.stackOffTop(&s16_a, 0));
    try expectEqual(9, utils.stackOffTop(&s16_a, 16));
}

test "basic RETURN" {
    // Store 0xff..ff at 0xff, expanding the memory size in the process, then return.
    const vm = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff52602060fff300");
    std.debug.print("vm.return_data = {any}, len = {d}\n", .{ vm.return_data, vm.return_data.len });
    try expectEqual(32, vm.return_data.len);
    for (vm.return_data) |i| {
        try expectEqual(0xff, i);
    }
}

test "basic REVERT" {
    // Store 0xff..ff at 0xff, expanding the memory size in the process, then revert.
    var sut: Sut = try .init(.{});
    defer sut.deinit();

    const res = sut.executeBasic("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff52602060fffd");
    try expectError(Exception.Revert, res);
    try expectEqual(32, sut.evm.return_data.len);
    for (sut.evm.return_data) |i| {
        try expectEqual(0xff, i);
    }
}

test "nonsense" {
    var sut: Sut = try .init(.{});
    defer sut.deinit();

    const res = sut.executeBasic("0c");
    try expectError(Exception.InvalidOp, res);
}

// TODO: These should be in evm.zig, here for now.
test "stack underflow" {
    // TODO: More scenarios?
    var sut: Sut = try .init(.{});
    defer sut.deinit();

    const res = sut.executeBasic("01");
    try expectError(Exception.StackUnderflow, res);
}

test "stack overflow" {
    // TODO: More scenarios?
    var sut: Sut = try .init(.{});
    defer sut.deinit();

    try sut.evm.stack.appendSlice(&[_]u256{1} ** 1024);
    try expectEqual(1024, sut.evm.stack.len);

    const res = sut.executeBasic("5f");
    try expectError(Exception.StackOverflow, res);
}

test "out of bounds bytecode STOP" {
    var sut: Sut = try .init(.{});
    defer sut.deinit();

    const stk = [_]u256{1} ** 2;

    try sut.evm.stack.appendSlice(&stk);
    try expectEqual(2, sut.evm.stack.len);

    // Attempt to access bytecode at non-existent index is a STOP.
    sut.evm.pc = 420;
    const res = sut.executeBasic("01");
    try expectEqual({}, res); // No error.
    try expectEqual(420, sut.evm.pc); // TODO: What does spec say, is pc +1 for the implicit STOP? So, 420 or 421 here?

    // Stack length and contents unchanged.
    try expectEqual(2, sut.evm.stack.len);
    try std.testing.expectEqualSlices(u256, &stk, sut.evm.stack.constSlice());

    // Essentially the same test except a happy case with implicit termination, we add 1 and 2
    //   and do not finish our bytecode with 0x00 (STOP). The top of the stack should still be 3
    //   and there should not be any error.
    var impl = try basicBytecode("6001600201");
    try expectEqual(1, impl.stack.len);
    try expectEqual(3, impl.stack.pop());
}

// Hacky and temporary (famous last words) from KECCAK256 to check two hash digests are equal
//   but if they aren't print the bytes not them as a number.
// TODO: Could probably do a better function as part of a custom test runner output.
// fn expectEqualBytes()
fn wordAsBytes(word: u256) [32]u8 {
    const the_bytes: [32]u8 = @bitCast(std.mem.nativeToBig(u256, word));
    return the_bytes;
}

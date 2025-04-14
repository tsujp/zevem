//! Dedicated to opcode testing to keep source file clean.
// There are A LOT of tests, if this is heresy we can simply paste this contents into said source file.

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const zevem = @import("zevem");
const util = zevem.util;
const EVM = zevem.EVM;
const basicBytecode = util.evmBasicBytecode;

// const evmError = @import("../evm.zig").EvmError;

// TODO: The same for this or move to that better API pattern I tore my hair out trying to do.
const DummyEnv = @import("../DummyEnv.zig");

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
    // s[1] is 0xff is -1 in two's complement, s[0] is 0 because 0 + 1 = 1 byte which is the size of s[1]; s[1] is extended completely to fill the word size (256 bits) meaning in this case all 256 bits are set to 1.
    var a01 = try basicBytecode("60ff5f0b00");
    try expect(a01.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    // 0x7f is 127 in two's complement which isn't negative so nothing is done.
    var a02 = try basicBytecode("607f5f0b00");
    try expect(a02.stack.pop() == 0x7f);

    var a03 = try basicBytecode("60fe5f0b00");
    try expect(a03.stack.pop() == 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe);

    var a04 = try basicBytecode("60b35f0b00");
    try expect(a04.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb3);

    // Uh oh! You provided s[0] as 1 forgetting it needs to be provided as the byte size minus 1, now SIGNEXTEND will read 2 bytes, but the MSBs will be zeroed thus this won't be a two's complement negative and so nothing will happen! D'oh! Git gudder n00b!
    var a05 = try basicBytecode("60ff60010b00");
    try expect(a05.stack.pop() == 0xff);

    // Some 32-bit two's complement negative.
    var a06 = try basicBytecode("63ad24465f60030b00");
    try expect(a06.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffad24465f);

    // There's nothing to do with a value that's already full-width.
    var a07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff601f0b00");
    try expect(a07.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    // If s[0] is given too low the result is unclobbered by "missed" more-significant bits.
    var a08 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60010b00");
    try expect(a08.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a09 = try basicBytecode("7effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff601e0b00");
    try expect(a09.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
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
    // Tests from: https://github.com/ethereum/go-ethereum/blob/e3d61e6db028c412f74bc4d4c7e117a9e29d0de0/core/vm/instructions_test.go#L132-L139

    var a01 = try basicBytecode("7fabcdef09080706050403020100000000000000000000000000000000000000005f1a00");
    try expect(a01.stack.pop() == 0xab);

    var a02 = try basicBytecode("7fabcdef090807060504030201000000000000000000000000000000000000000060011a00");
    try expect(a02.stack.pop() == 0xcd);

    var a03 = try basicBytecode("7f00cdef090807060504030201ffffffffffffffffffffffffffffffffffffffff5f1a00");
    try expect(a03.stack.pop() == 0);

    var a04 = try basicBytecode("7f00cdef090807060504030201ffffffffffffffffffffffffffffffffffffffff60011a00");
    try expect(a04.stack.pop() == 0xcd);

    var a05 = try basicBytecode("7f0000000000000000000000000000000000000000000000000000000000102030601f1a00");
    try expect(a05.stack.pop() == 0x30);

    var a06 = try basicBytecode("7f0000000000000000000000000000000000000000000000000000000000102030601e1a00");
    try expect(a06.stack.pop() == 0x20);

    var a07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60201a00");
    try expect(a07.stack.pop() == 0);

    var a08 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff67ffffffffffffffff1a00");
    try expect(a08.stack.pop() == 0);
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
    // Tests from: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-145.md#sar-arithmetic-shift-right

    var a01 = try basicBytecode("60015f1d00");
    try expect(a01.stack.pop() == 1);

    var a02 = try basicBytecode("600160011d00");
    try expect(a02.stack.pop() == 0);

    var a03 = try basicBytecode("7f800000000000000000000000000000000000000000000000000000000000000060011d00");
    try expect(a03.stack.pop() == 0xc000000000000000000000000000000000000000000000000000000000000000);

    var a04 = try basicBytecode("7f800000000000000000000000000000000000000000000000000000000000000060ff1d00");
    try expect(a04.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a05 = try basicBytecode("7f80000000000000000000000000000000000000000000000000000000000000006101001d00");
    try expect(a05.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a06 = try basicBytecode("7f80000000000000000000000000000000000000000000000000000000000000006101011d00");
    try expect(a06.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a07 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f1d00");
    try expect(a07.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a08 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60011d00");
    try expect(a08.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a09 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff1d00");
    try expect(a09.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a10 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6101001d00");
    try expect(a10.stack.pop() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    var a11 = try basicBytecode("5f60011d00");
    try expect(a11.stack.pop() == 0);

    var a12 = try basicBytecode("7f400000000000000000000000000000000000000000000000000000000000000060fe1d00");
    try expect(a12.stack.pop() == 1);

    var a13 = try basicBytecode("7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60f81d00");
    try expect(a13.stack.pop() == 0x7f);

    var a14 = try basicBytecode("7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60fe1d00");
    try expect(a14.stack.pop() == 1);

    var a15 = try basicBytecode("7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff1d00");
    try expect(a15.stack.pop() == 0);

    var a16 = try basicBytecode("7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6101001d00");
    try expect(a16.stack.pop() == 0);
}

test "basic KECCAK256" {
    // TODO:
}

test "basic BALANCE" {
    // TODO:
}

test "basic POP" {
    // Push 2 items, pop twice for great success!
    const a = try basicBytecode("600161cafe505000");
    try expect(a.stack.len == 0);

    // Push 2 items, pop one leaving the first-pushed item at the top.
    var b = try basicBytecode("61cafe61babe5000");
    try expect(b.stack.len == 1);
    try expect(b.stack.pop() == 0xcafe);

    // TODO: Here and for many others do we want custom error types per opcode to test failing cases like this?
    // Push 2 items, but then try and pop 3 times.
    // const c = basicBytecode("5f600150505000");
    // try expect(c == error.Pop);
}

// TODO: Put elsewhere, fine here (for now).
fn printMemory(mem: std.ArrayListUnmanaged(u8)) void {
    const print = std.debug.print;

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

test "basic MSTORE" {
    // Store 0xff..ff at 0xff, expanding the memory size in the process.
    const vm1 = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff5200");
    try expect(vm1.stack.len == 0);
    std.debug.print("vm.mem.items = {any}\n", .{vm1.mem.items.len});
    printMemory(vm1.mem);
    try expect(vm1.mem.items.len == 255 + 32);
    for (0..0xff) |i| {
        try expect(vm1.mem.items[i] == 0);
    }
    for (0xff..0xff + 32) |i| {
        try expect(vm1.mem.items[i] == 0xff);
    }

    // Swap the two arguments, to check if an overflow is detected
    const overflow_result = basicBytecode("60ff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5200");
    try expect(overflow_result == error.MemResizeUInt256Overflow);

    // Check the temporary condition that resizing the memory to an
    // incredible value is going to fail.
    const resize_error = basicBytecode("60ff7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0005200");
    try expect(resize_error == error.OutOfMemory);

    // Check overwritten memory is correctly zeroed.
    // From: https://github.com/ethereum/go-ethereum/blob/32c6aa8a1a2595cbb89b05f93440d230841f8431/core/vm/instructions_test.go#L520
    const overwrites = try basicBytecode("7fabcdef00000000000000abba000000000deaf000000c0de001000000001337005f5260015f5200");
    try expect(overwrites.stack.len == 0);
    try expect(overwrites.mem.items.len == 32);
    printMemory(overwrites.mem);
    try expect(std.mem.readInt(u256, overwrites.mem.items[0..32], .big) == 1);
}

// TODO: Add super, super basic tests for PUSH0 .. PUSH32. Basically just one scenario per PUSHN because they are used in essentially every other test.

test "basic DUP" {
    // DUP1
    var d01_a = try basicBytecode("5f8000");
    try expectEqual(d01_a.stack.pop(), 0);

    var d01_b = try basicBytecode("5f60018000");
    try expectEqual(d01_b.stack.pop(), 1);

    var d01_c = try basicBytecode("5f80808000");
    try expectEqual(d01_c.stack.len, 4);
    try expectEqual(d01_c.stack.pop(), 0);

    // DUP2
    var d02_a = try basicBytecode("60025f8100");
    try expectEqual(d02_a.stack.pop(), 2);

    var d02_b = try basicBytecode("5f60025f8100");
    try expectEqual(d02_b.stack.pop(), 2);

    // DUP3
    var d03_a = try basicBytecode("600c600a5f8200");
    try expectEqual(d03_a.stack.pop(), 0xc);

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

test "basic RETURN" {
    // Store 0xff..ff at 0xff, expanding the memory size in the process, then return.
    const vm = try basicBytecode("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff52602060fff300");
    std.debug.print("vm.return_data = {any}, len = {d}\n", .{ vm.return_data, vm.return_data.len });
    try expect(vm.return_data.len == 32);
    for (vm.return_data) |i| {
        try expect(i == 0xff);
    }
}

test "basic REVERT" {
    // Store 0xff..ff at 0xff, expanding the memory size in the process, then revert.
    var dummyEnv: DummyEnv = .{};

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator, &dummyEnv);
    const err = evm.execute(&util.htb("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60ff52602060fffd"));
    try expect(err == error.Revert);
    // try expect(evm == error.Revert);
    try expect(evm.return_data.len == 32);
    for (evm.return_data) |i| {
        try expect(i == 0xff);
    }
}

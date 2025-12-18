//! Gas execution testing.

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

fn consumed(amount: u64) u64 {
    return 21_000 + amount;
}

fn gas(evm: EVM) u64 {
    return 100_000 - evm.gas;
}

test "basic OutOfGas" {
    // Attempt to execute a transcation whose T_g (gas limit) is less than the g_0 (intrinsic
    //   gas cost prior to execution) minimum; currently 21_000 (G_transaction). This should
    //   result in an out-of-gas error.
    var sut: Sut = try .init(.{});
    defer sut.deinit();

    const res = sut.evm.execute(tx(.{
        .sender = 0,
        .value = 0,
        .gas = 123,
        .code = "0100",
        .data = "",
    }));

    try expectError(Exception.OutOfGas, res);
    try expectEqual(123, sut.evm.gas); // Gas same as input (nothing done). [TODO: Is this correct or does it go to 0 etc etc]
}

test "basic consumption" {
    // Conversely if we have a T_g of 21_000 and execute something which consumes no gas like
    //   the STOP op, that should succeed.
    var sut: Sut = try .init(.{});
    defer sut.deinit();

    const res = sut.evm.execute(tx(.{
        .sender = 0,
        .value = 0,
        .gas = 21_000,
        .code = "00",
        .data = "",
    }));

    try expectEqual(0, sut.evm.gas); // All gas consumed until zero (which is NOT an error).
    try expectEqual({}, res); // No error.
    try expectEqual(1, sut.evm.pc); // TODO: What does spec say, is pc +1 for the implicit STOP? So, 0 or 1 here?
}

// Opcodes which have constant gas pricing.
test "constant pricing" {
    // TODO
    return error.SkipZigTest;
}

// TODO: Dynamic gas pricing.
test "dynamic" {
    // TODO: Might be able to put sut here and just 'reset' it in each test scenario instead of an entire create/defer per test scenario.

    {
        // Exponent of 0 is effectively constant G_exp cost.
        const a01 = try basicBytecode("5f60010a00");
        try expectEqual(consumed(15), gas(a01));

        // Small non-zero exponent is effectively constant G_exp + G_expbyte.
        const a02 = try basicBytecode("600360020a00");
        try expectEqual(consumed(66), gas(a02));

        const a03 = try basicBytecode("7f8f965a06da0ac41dcb3a34f1d8ab7d8fee620a94faa42c395997756b007ffeff60ff0a00");
        try expectEqual(consumed(1_616), gas(a03));
    }
}

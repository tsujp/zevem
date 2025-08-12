const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const zevem = @import("zevem");
const util = zevem.util;
const EVM = zevem.EVM;
const basicBytecode = util.evmBasicBytecode;

const EvmError = @import("../evm.zig").EvmError;

const DummyEnv = @import("../DummyEnv.zig");

test "basic OutOfGas" {
    // Create an EVM and set it's T_g (gas limit) to zero, now g_0 (intrinsic gas cost prior to
    //   execution) won't be enough to cover the minimum possible value of 21_000 (G_transaction)
    //   and so we should get an error.

    var dummyEnv: DummyEnv = .default;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var evm = try EVM.init(allocator, &dummyEnv);

    // Not enough gas to cover g_0 minimum.
    evm.gas = 123;

    const err = evm.execute(&util.htb("00"));
    try expectError(EvmError.OutOfGas, err);
}

test "basic consumption" {
    // Conversely if we have a T_g of 21_000 and execute something which consumes no gas like
    //   the STOP op, that should succeed.
    var dummyEnv: DummyEnv = .default;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var evm = try EVM.init(allocator, &dummyEnv);

    evm.gas = 21_000;

    const res = try evm.execute(&util.htb("00"));

    try expectEqual({}, res); // No error.
    try expectEqual(1, evm.pc); // TODO: What does spec say, is pc +1 for the implicit STOP? So, 0 or 1 here?
}

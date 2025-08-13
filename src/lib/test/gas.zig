const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const zevem = @import("zevem");
const util = zevem.util;
const EVM = zevem.EVM;

const basicBytecode = util.evmBasicBytecode;
const tx = util.testTx;

const EvmError = @import("../evm.zig").EvmError;

const DummyEnv = @import("../DummyEnv.zig");

test "basic OutOfGas" {
    // Attempt to execute a transcation whose T_g (gas limit) is less than the g_0 (intrinsic
    //   gas cost prior to execution) minimum; currently 21_000 (G_transaction). This should
    //   result in an out-of-gas error.

    var dummyEnv: DummyEnv = .default;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var evm = try EVM.init(allocator, &dummyEnv);

    const err = evm.execute(tx(.{ .gas = 123, .data = "0100", }));
    try expectError(EvmError.OutOfGas, err);
}

test "basic consumption" {
    // Conversely if we have a T_g of 21_000 and execute something which consumes no gas like
    //   the STOP op, that should succeed.
    var dummyEnv: DummyEnv = .default;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var evm = try EVM.init(allocator, &dummyEnv);

    const res = try evm.execute(tx(.{ .gas = 21_000, .data = "00", }));

    try expectEqual(0, evm.gas); // All gas consumed until zero (which is NOT an error).
    try expectEqual({}, res); // No error.
    try expectEqual(1, evm.pc); // TODO: What does spec say, is pc +1 for the implicit STOP? So, 0 or 1 here?
}

// Opcodes which have constant gas pricing.
test "constant pricing" {
    
}

// TODO: Dynamic gas pricing.

const std = @import("std");
const NewEVM = @import("evm.zig").NewEVM;

pub const DummyEnv = struct {
    pub fn getBalance(_: *DummyEnv, _: u256) !u256 {
        return 0;
    }
};
pub const EVM = NewEVM(DummyEnv);

// TODO: Place elsewhere, idk.
// Inspired by: https://github.com/jsign/phant/blob/18eeadffd24de9c6b3ae5c7505ada52c43f2b1d4/src/common/hexutils.zig#L73
pub inline fn htb(comptime bytes: []const u8) [bytes.len / 2]u8 {
    comptime var buf: [bytes.len / 2]u8 = undefined;
    _ = comptime std.fmt.hexToBytes(&buf, bytes) catch @compileError("htb hex to bytes error");
    return buf;
}

// TODO: Replace this with test files on-disk which are read to execute EVM instructions and then the unit test in Zig code is about asserting expected values; or do it all in-code but in any case abstract creation of EVM.
// TODO: Probably also want some re-usable one to avoid re-allocating every single time in these unit tests? But fresh context is important, but also testing properly is important.
pub fn evmBasicBytecode(comptime bytes: []const u8) !EVM {
    var dummyEnv: DummyEnv = .{};
    var evm = try EVM.init(&dummyEnv);
    try evm.execute(&htb(bytes));

    return evm;
}

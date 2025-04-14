//! Library (zevem) root.

const std = @import("std");
const evm = @import("lib/evm.zig");
pub const DummyEnv = @import("lib/DummyEnv.zig");

test {
    std.testing.refAllDeclsRecursive(@This());

    // Tests under lib/test are for convenience as they include a lot of cases.
    _ = @import("lib/test/opcode.zig");
}

// TODO: test-filter now works as expected. It looks like under the old setup before this commit that test filter broke after lib.test. but im unsure why that would be the case. Try and get a minimal reproduction to see what the issue is and report the bug.

pub const EVM = evm.New(DummyEnv);

pub const util = struct {
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

        var gpa: std.heap.DebugAllocator(.{}) = .init;
        const allocator = gpa.allocator();

        var evm_dummy = try EVM.init(allocator, &dummyEnv);
        try evm_dummy.execute(&htb(bytes));

        return evm_dummy;
    }
};

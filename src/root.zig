//! Library (zevem) root.

const std = @import("std");
const builtin = @import("builtin");

pub const evm = @import("lib/evm.zig");
pub const DummyEnv = @import("lib/DummyEnv.zig");

test {
    std.testing.refAllDeclsRecursive(@This());

    // Tests under lib/test are for convenience as they include a lot of cases.
    _ = @import("lib/test/opcode.zig");
    _ = @import("lib/test/gas.zig");
}

// TODO: test-filter now works as expected. It looks like under the old setup before this commit that test filter broke after lib.test. but im unsure why that would be the case. Try and get a minimal reproduction to see what the issue is and report the bug.

pub const EVM = evm.New(DummyEnv);

const Transaction = @import("lib/types.zig").Transaction;
pub const util = struct {
    // TODO: Place elsewhere, idk.
    // Inspired by: https://github.com/jsign/phant/blob/18eeadffd24de9c6b3ae5c7505ada52c43f2b1d4/src/common/hexutils.zig#L73
    pub fn htb(comptime bytes: []const u8) [bytes.len / 2]u8 {
        comptime var buf: [bytes.len / 2]u8 = undefined;
        _ = comptime std.fmt.hexToBytes(&buf, bytes) catch @compileError("htb hex to bytes error");
        return buf;
    }

    // System Under Test (and avoid overloading the term 'EVM').
    // XXX: I don't know if it's (easy) to make this generic over any environment, so only
    //      DummyEnv for now.
    pub const Sut = struct {
        // Need to hold these in (this) wrapping struct so they aren't destroyed...
        gpa: std.heap.DebugAllocator(.{}),
        // alloc: std.mem.Allocator, // XXX: Cannot get deinit from Allocator since ptr is opaque.
        env: DummyEnv,
        // ...because evm requires them.
        evm: evm.New(DummyEnv),

        pub fn init(comptime args: struct {
            env: DummyEnv = .default,
            gpa: std.heap.DebugAllocator(.{}) = .init,
            // gpa: std.heap.DebugAllocator(.{}) = .{ .backing_allocator = std.testing.allocator },
        }) !Sut {
            if (!builtin.is_test) @compileError("this function is for use in tests only");

            // Copy arg fields (TODO: struct destructure instead..?)
            var gpa = args.gpa;
            // const alloc = gpa.allocator();
            var env = args.env;

            // const evm_sut = try evm.New(env_copy).init(
            const evm_sut = try evm.New(DummyEnv).init(
                gpa.allocator(),
                // alloc,
                &env,
            );

            return Sut{
                .gpa = gpa, // To stop it being destroyed once init out of scope.
                // .alloc = alloc,
                .env = env, // Ditto.
                .evm = evm_sut,
            };
        }

        pub fn deinit(self: *Sut) void {
            if (self.gpa.deinit() == .leak) {
                @panic("TEST MEMORY LEAK");
            }
        }

        pub fn executeBasic(self: *Sut, comptime bytes: []const u8) !void {
            if (!builtin.is_test) @compileError("this function is for use in tests only");

            const res = try self.evm.execute(.{
                .gas = 100_000, // Arbitrary, should be enough to cover all _basic_ test cases.
                .data = &htb(bytes),
            });

            return res;
        }
    };

    // TODO: Replace this with test files on-disk which are read to execute EVM instructions and then the unit test in Zig code is about asserting expected values; or do it all in-code but in any case abstract creation of EVM.
    // TODO: Probably also want some re-usable one to avoid re-allocating every single time in these unit tests? But fresh context is important, but also testing properly is important.
    pub fn evmBasicBytecode(comptime bytes: []const u8) !EVM {
        if (!builtin.is_test) @compileError("this function is for use in tests only");

        var dummyEnv: DummyEnv = .default;

        var gpa: std.heap.DebugAllocator(.{}) = .init;
        const allocator = gpa.allocator();

        var evm_dummy = try EVM.init(allocator, &dummyEnv);
        try evm_dummy.execute(&htb(bytes));

        return evm_dummy;
    }

    // Dumb convenience function to automatically call htb on data.
    pub fn testTx(comptime tx: Transaction) Transaction {
        if (!builtin.is_test) @compileError("this function is for use in tests only");

        var new_tx = tx;
        new_tx.data = &htb(tx.data);

        return new_tx;
    }
};

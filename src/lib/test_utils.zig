//! Utilities to help with testing.

const std = @import("std");
const builtin = @import("builtin");

const zevem = @import("zevem");

const evm = zevem.evm;
const DummyEnv = zevem.DummyEnv;
const Transaction = zevem.evm.types.Transaction;
const htb = zevem.utils.htb;
const EVM = zevem.EVM;

// System Under Test (and avoid overloading the term 'EVM').
// XXX: I don't know if it's (easy) to make this generic over any environment, so only
//      DummyEnv for now.
pub const Sut = struct {
    const Self = @This();

    // Need to hold ptr to environment in wrapping struct for lifetime access...
    env: *DummyEnv,
    // ...required by evm.
    evm: evm.New(DummyEnv),

    pub fn init(args: struct {
        env: DummyEnv = .default,
    }) !Self {
        if (!builtin.is_test) @compileError("this function is for use in tests only");

        // Allocate env on heap otherwise it'll be a dangling pointer.
        const ptr = try std.testing.allocator.create(DummyEnv);
        ptr.* = args.env;

        const soot = Self{
            .env = ptr,
            .evm = try evm.New(DummyEnv).init(std.testing.allocator, ptr),
        };

        return soot;
    }

    pub fn deinit(self: *Self) void {
        self.evm.deinit();
        std.testing.allocator.destroy(self.env);
    }

    // Caller can provide bytecode as string, and can avoid use of `try` and still get the
    //   execution result or the expected error.
    pub fn executeBasic(self: *Self, comptime bytes: []const u8) !void {
        if (!builtin.is_test) @compileError("this function is for use in tests only");

        const txx = Transaction{
            .gas = 100_000, // Arbitrary, should be enough to cover all _basic_ test cases.
            .data = &htb(bytes),
        };

        try self.evm.execute(txx);
    }
};

// TODO: Probably also want some re-usable one to avoid re-allocating every single time in these unit tests? But fresh context is important, but also testing properly is important.
pub fn evmBasicBytecode(comptime bytes: []const u8) !EVM {
    if (!builtin.is_test) @compileError("this function is for use in tests only");

    var dummyEnv: DummyEnv = .default;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var evm_dummy = try EVM.init(allocator, &dummyEnv);
    try evm_dummy.execute(.{
        .gas = 100_000, // Arbitrary, should be enough to cover all _basic_ test cases.
        .data = &htb(bytes),
    });

    return evm_dummy;
}

// Dumb convenience function to automatically call htb on data.
pub fn tx(comptime base_tx: Transaction) Transaction {
    if (!builtin.is_test) @compileError("this function is for use in tests only");

    var new_tx = base_tx;

    // Force inline copy at compile-time.
    new_tx.data = comptime &htb(base_tx.data);

    return new_tx;
}

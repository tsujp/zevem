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
    // Need to hold these in (this) wrapping struct so they aren't destroyed...
    gpa: std.heap.DebugAllocator(.{}),
    env: DummyEnv,
    // ...because evm requires them.
    evm: evm.New(DummyEnv),

    pub fn init(comptime args: struct {
        env: DummyEnv = .default,
        gpa: std.heap.DebugAllocator(.{}) = .init,
    }) !Sut {
        if (!builtin.is_test) @compileError("this function is for use in tests only");

        // Copy arg fields (TODO: struct destructure instead..?)
        var gpa = args.gpa;
        var env = args.env;

        // const evm_sut = try evm.New(env_copy).init(
        const evm_sut = try evm.New(DummyEnv).init(
            gpa.allocator(),
            &env,
        );

        return Sut{
            .gpa = gpa, // To stop it being destroyed once init out of scope.
            .env = env, // Ditto.
            .evm = evm_sut,
        };
    }

    pub fn deinit(self: *Sut) void {
        if (self.gpa.deinit() == .leak) {
            @panic("TEST MEMORY LEAK");
        }
    }

    // Caller can provide bytecode as string, and can avoid use of `try` and still get the
    //   execution result or the expected error.
    pub fn executeBasic(self: *Sut, comptime bytes: []const u8) !void {
        if (!builtin.is_test) @compileError("this function is for use in tests only");

        const res = try self.evm.execute(.{
            .gas = 100_000, // Arbitrary, should be enough to cover all _basic_ test cases.
            .data = &htb(bytes),
        });

        return res;
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
    new_tx.data = &htb(base_tx.data);

    return new_tx;
}

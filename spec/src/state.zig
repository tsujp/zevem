//! In-memory world state (σ) for the spec harness: a flat map of accounts with
//! storage, plus state root computation over it.
//!
//! All allocation is assumed arena-backed (one arena per executed test case),
//! so nothing is individually freed and clones are cheap to reason about.

const std = @import("std");
const Keccak256 = std.crypto.hash.sha3.Keccak256;

const rlp = @import("rlp.zig");
const trie = @import("trie.zig");

const Bytes = std.ArrayListUnmanaged(u8);

pub const Address = u160;

pub const Account = struct {
    nonce: u64 = 0,
    balance: u256 = 0,
    code: []const u8 = &.{},
    storage: std.AutoHashMapUnmanaged(u256, u256) = .empty,

    /// Empty per EIP-161: no code, zero nonce, zero balance.
    pub fn isEmpty(self: *const Account) bool {
        return self.nonce == 0 and self.balance == 0 and self.code.len == 0;
    }
};

pub const StateDB = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    accounts: std.AutoHashMapUnmanaged(Address, Account),

    pub fn init(alloc: std.mem.Allocator) Self {
        return .{ .alloc = alloc, .accounts = .empty };
    }

    pub fn get(self: *Self, addr: Address) ?*Account {
        return self.accounts.getPtr(addr);
    }

    pub fn getOrCreate(self: *Self, addr: Address) !*Account {
        const gop = try self.accounts.getOrPut(self.alloc, addr);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        return gop.value_ptr;
    }

    pub fn balanceOf(self: *Self, addr: Address) u256 {
        return if (self.get(addr)) |account| account.balance else 0;
    }

    pub fn addBalance(self: *Self, addr: Address, amount: u256) !void {
        const account = try self.getOrCreate(addr);
        account.balance += amount;
    }

    pub fn setStorage(self: *Self, addr: Address, key: u256, value: u256) !void {
        const account = try self.getOrCreate(addr);
        if (value == 0) {
            _ = account.storage.remove(key);
        } else {
            try account.storage.put(self.alloc, key, value);
        }
    }

    pub fn delete(self: *Self, addr: Address) void {
        _ = self.accounts.remove(addr);
    }

    /// Deep copy, for snapshot/revert semantics around transaction execution.
    pub fn clone(self: *Self) !Self {
        var copy = Self.init(self.alloc);
        var it = self.accounts.iterator();
        while (it.next()) |kv| {
            const account = kv.value_ptr;
            try copy.accounts.put(self.alloc, kv.key_ptr.*, .{
                .nonce = account.nonce,
                .balance = account.balance,
                // Code is never mutated in place, share the slice.
                .code = account.code,
                .storage = try account.storage.clone(self.alloc),
            });
        }
        return copy;
    }

    /// World state root: secure trie over RLP-encoded account bodies.
    /// Ref: YP 4.1.
    pub fn root(self: *Self) ![32]u8 {
        const pairs = try self.alloc.alloc(trie.Pair, self.accounts.count());

        var it = self.accounts.iterator();
        var i: usize = 0;
        while (it.next()) |kv| : (i += 1) {
            const key = try self.alloc.alloc(u8, 20);
            std.mem.writeInt(u160, key[0..20], kv.key_ptr.*, .big);

            pairs[i] = .{ .key = key, .value = try encodeAccount(self.alloc, kv.value_ptr) };
        }

        return trie.secureRoot(self.alloc, pairs);
    }

    /// Account body: RLP([nonce, balance, storage root, code hash]).
    fn encodeAccount(alloc: std.mem.Allocator, account: *const Account) ![]const u8 {
        var payload: Bytes = .empty;
        try rlp.encodeUint(alloc, &payload, account.nonce);
        try rlp.encodeUint(alloc, &payload, account.balance);

        const storage_root = try storageRoot(alloc, account);
        try rlp.encodeBytes(alloc, &payload, &storage_root);

        var code_hash: [32]u8 = undefined;
        Keccak256.hash(account.code, &code_hash, .{});
        try rlp.encodeBytes(alloc, &payload, &code_hash);

        var body: Bytes = .empty;
        try rlp.encodeList(alloc, &body, payload.items);
        return body.items;
    }

    /// Storage root: secure trie keyed by the 32-byte slot, holding the
    /// RLP-encoded (minimal big-endian) value. Zero values are absent.
    fn storageRoot(alloc: std.mem.Allocator, account: *const Account) ![32]u8 {
        if (account.storage.count() == 0) return trie.EMPTY_ROOT;

        const pairs = try alloc.alloc(trie.Pair, account.storage.count());

        var it = account.storage.iterator();
        var i: usize = 0;
        while (it.next()) |kv| : (i += 1) {
            std.debug.assert(kv.value_ptr.* != 0);

            const key = try alloc.alloc(u8, 32);
            std.mem.writeInt(u256, key[0..32], kv.key_ptr.*, .big);

            var value: Bytes = .empty;
            try rlp.encodeUint(alloc, &value, kv.value_ptr.*);

            pairs[i] = .{ .key = key, .value = value.items };
        }

        return trie.secureRoot(alloc, pairs);
    }
};

test "state root of empty state is the empty trie root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var state = StateDB.init(arena.allocator());
    try std.testing.expectEqual(trie.EMPTY_ROOT, try state.root());
}

test "state root matches execution-spec-tests fixture" {
    // Post state of test_cover_revert[fork_Cancun-state_test] from EEST v5.4.0
    // (fixtures/state_tests/frontier/opcodes/test_cover_revert.json), whose
    // fixture-declared post hash is below. Exercises account encoding and a
    // two-leaf trie against externally produced ground truth.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var state = StateDB.init(arena.allocator());

    const sender = try state.getOrCreate(0x0a16f360235334164b5f50ca2fa0d37e420cedb8);
    sender.nonce = 0x01;
    sender.balance = 0x3635c9adc5de94848c;

    const coinbase = try state.getOrCreate(0x2adc25665018aa1fe0e6bc666dac8fc2697ff9ba);
    coinbase.balance = 0x0371d6;

    var expected: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, "dfe3e551e5a9ad38d8e078915698609e11a4fdd5fd4c0db4213a4532ab34ccee");

    try std.testing.expectEqual(expected, try state.root());
}

test "storage values participate in the state root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var state = StateDB.init(arena.allocator());
    _ = try state.getOrCreate(0x0a16f360235334164b5f50ca2fa0d37e420cedb8);

    const without_storage = try state.root();

    try state.setStorage(0x0a16f360235334164b5f50ca2fa0d37e420cedb8, 1, 2);
    const with_storage = try state.root();

    try std.testing.expect(!std.mem.eql(u8, &without_storage, &with_storage));

    // Writing zero clears the slot and restores the prior root.
    try state.setStorage(0x0a16f360235334164b5f50ca2fa0d37e420cedb8, 1, 0);
    try std.testing.expectEqual(without_storage, try state.root());
}

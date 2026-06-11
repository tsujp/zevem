//! Executes parsed state test fixtures against zevem and verifies the
//! resulting world state.
//!
//! The harness acts as zevem's host: it owns the world state, applies the
//! state transition surrounding EVM execution (YP section 6), invokes zevem
//! for code execution, and verifies the post state both account-by-account
//! and via the state root declared by the fixture.
//!
//! Cancun rules only. Anything the harness or zevem cannot faithfully execute
//! is reported as a skip with a reason, never silently dropped.

const std = @import("std");
const Keccak256 = std.crypto.hash.sha3.Keccak256;

const zevem = @import("zevem");

const fixture = @import("fixture.zig");
const rlp = @import("rlp.zig");
const statefile = @import("state.zig");

const StateDB = statefile.StateDB;
const Address = statefile.Address;

// NB: evm.New is generic over the environment but op.zig's dynamic gas
// function pointers are typed against New(DummyEnv) specifically, so any
// other environment type fails to instantiate; the harness therefore drives
// DummyEnv directly. Its fields cover everything the EVM reads today except
// per-address balances (DummyEnv.getBalance is hardcoded to zero), which only
// the unfinished BALANCE opcode consumes.
const EVM = zevem.EVM;
const Exception = zevem.evm.Exception;

/// Keccak-256 of RLP(()); the logs hash of an empty log series.
const EMPTY_LOGS_HASH = [32]u8{
    0x1d, 0xcc, 0x4d, 0xe8, 0xde, 0xc7, 0x5d, 0x7a, 0xab, 0x85, 0xb5, 0x67, 0xb6, 0xcc, 0xd4, 0x1a,
    0xd3, 0x12, 0x45, 0x1b, 0x94, 0x8a, 0x74, 0x13, 0xf0, 0xa1, 0x42, 0xfd, 0x40, 0xd4, 0x93, 0x47,
};

// Cancun protocol parameters.
const MAX_CODE_SIZE = 24_576; // EIP-170
const MAX_INITCODE_SIZE = 2 * MAX_CODE_SIZE; // EIP-3860
const G_TRANSACTION = 21_000;
const G_TXDATA_ZERO = 4;
const G_TXDATA_NONZERO = 16;
const G_TXCREATE = 32_000;
const G_INITCODE_WORD = 2;
const G_ACCESS_LIST_ADDRESS = 2_400;
const G_ACCESS_LIST_STORAGE_KEY = 1_900;
const G_CODE_DEPOSIT = 200;

pub const SkipReason = enum {
    /// Post entries for forks other than the one requested.
    fork_filtered,
    /// Transaction type the harness does not execute (blob, set-code).
    tx_type_unsupported,
    /// zevem returned Exception.NotImplemented (opcode pending).
    evm_unimplemented,
    /// zevem requested host orchestration (CREATE/CALL family); resumable
    /// execution is not finished on the zevem side yet.
    evm_orchestrate,
    /// The transaction targets a precompiled contract; precompiles are not
    /// implemented (in zevem or the harness) yet.
    precompile_unsupported,
    /// The fixture expects log output; zevem does not collect logs yet so the
    /// declared logs hash cannot be verified.
    logs_uncollected,
    /// A harness limitation (e.g. value does not fit the type zevem uses).
    harness_limit,

    pub fn describe(self: SkipReason) []const u8 {
        return switch (self) {
            .fork_filtered => "post entries for a non-selected fork",
            .tx_type_unsupported => "unsupported transaction type (blob or set-code)",
            .evm_unimplemented => "opcode not implemented by zevem yet",
            .evm_orchestrate => "needs host orchestration (CREATE/CALL pending in zevem)",
            .precompile_unsupported => "transaction targets a precompile; precompiles pending",
            .logs_uncollected => "fixture expects logs; zevem does not collect logs yet",
            .harness_limit => "harness limitation",
        };
    }
};

pub const Outcome = union(enum) {
    /// Executed and the post state (accounts and root) matched.
    pass,
    /// Transaction was rejected and the fixture expected a rejection; the
    /// (unchanged) post state matched.
    pass_exception,
    fail: []const u8,
    skip: SkipReason,
};

pub const EntryResult = struct {
    case_name: []const u8,
    fork: []const u8,
    entry_index: usize,
    outcome: Outcome,
};

/// Run every post entry of `case` whose fork matches `fork_filter`, appending
/// to `results`. `alloc` must be an arena; per-entry state is built fresh so
/// entries are independent.
pub fn runCase(
    alloc: std.mem.Allocator,
    case: fixture.TestCase,
    fork_filter: []const u8,
    results: *std.ArrayListUnmanaged(EntryResult),
) !void {
    for (case.posts) |post| {
        const matches = std.mem.eql(u8, post.fork, fork_filter);

        for (post.entries, 0..) |entry, i| {
            const outcome = if (!matches)
                Outcome{ .skip = .fork_filtered }
            else
                runEntry(alloc, case, entry) catch |err| switch (err) {
                    error.OutOfMemory => return err,
                };

            try results.append(alloc, .{
                .case_name = case.name,
                .fork = post.fork,
                .entry_index = i,
                .outcome = outcome,
            });
        }
    }
}

fn runEntry(
    alloc: std.mem.Allocator,
    case: fixture.TestCase,
    entry: fixture.PostEntry,
) error{OutOfMemory}!Outcome {
    const tx = case.transaction;

    if (tx.has_blobs or tx.has_authorizations) return .{ .skip = .tx_type_unsupported };

    // Select the concrete transaction this post entry describes.
    if (entry.gas_index >= tx.gas_limits.len or
        entry.value_index >= tx.values.len or
        entry.data_index >= tx.datas.len)
    {
        return .{ .fail = "post entry indexes out of range of transaction vectors" };
    }

    const gas_limit_wide = tx.gas_limits[entry.gas_index];
    const value = tx.values[entry.value_index];
    const data = tx.datas[entry.data_index];
    const access_list: []const fixture.AccessListEntry = if (tx.access_lists) |lists| blk: {
        if (entry.data_index >= lists.len) return .{ .fail = "access list vector shorter than data vector" };
        break :blk lists[entry.data_index];
    } else &.{};

    // Build the pre state.
    var state = StateDB.init(alloc);
    for (case.pre) |account| try loadAccount(&state, account);

    // Apply the state transition; on a validation failure the state is left
    // untouched and the fixture is expected to declare an exception.
    const rejection = try applyTransaction(alloc, &state, case, .{
        .gas_limit_wide = gas_limit_wide,
        .value = value,
        .data = data,
        .access_list = access_list,
    });

    switch (rejection) {
        .executed => {
            if (entry.expect_exception) |exception| {
                return .{ .fail = try std.fmt.allocPrint(
                    alloc,
                    "fixture expects transaction exception ({s}) but the transaction was accepted",
                    .{exception},
                ) };
            }
        },
        .invalid => |reason| {
            if (entry.expect_exception == null) {
                return .{ .fail = try std.fmt.allocPrint(
                    alloc,
                    "transaction rejected ({s}) but fixture expects acceptance",
                    .{reason},
                ) };
            }
            // Expected rejection; fall through to post-state verification of
            // the untouched state.
        },
        .skipped => |reason| return .{ .skip = reason },
    }

    // The fixture's logs hash is unverifiable while zevem does not collect
    // logs; only the empty hash can be confirmed.
    if (!std.mem.eql(u8, &entry.logs_hash, &EMPTY_LOGS_HASH)) {
        return .{ .skip = .logs_uncollected };
    }

    if (try diffState(alloc, &state, entry.state)) |diff| return .{ .fail = diff };

    const root = try state.root();
    if (!std.mem.eql(u8, &root, &entry.hash)) {
        return .{ .fail = try std.fmt.allocPrint(
            alloc,
            "accounts match the fixture but the state root does not (got {x}, want {x}); harness trie bug",
            .{ &root, &entry.hash },
        ) };
    }

    return if (rejection == .invalid) .pass_exception else .pass;
}

fn loadAccount(state: *StateDB, account: fixture.Account) !void {
    const loaded = try state.getOrCreate(account.address);
    loaded.nonce = account.nonce;
    loaded.balance = account.balance;
    loaded.code = account.code;
    for (account.storage) |slot| {
        try state.setStorage(account.address, slot.key, slot.value);
    }
}

const ConcreteTx = struct {
    gas_limit_wide: u256,
    value: u256,
    data: []const u8,
    access_list: []const fixture.AccessListEntry,
};

const TransitionResult = union(enum) {
    executed,
    /// Transaction validation failed; state unchanged.
    invalid: []const u8,
    skipped: SkipReason,
};

/// State transition for one transaction: YP section 6 (Cancun rules), with
/// zevem providing code execution.
fn applyTransaction(
    alloc: std.mem.Allocator,
    state: *StateDB,
    case: fixture.TestCase,
    tx: ConcreteTx,
) error{OutOfMemory}!TransitionResult {
    const env = case.env;
    const declared = case.transaction;
    const is_creation = declared.to == null;

    // ////////////////////////////////////////////////////////////////////////
    // //////////////// Validation. No state is modified before all checks pass.

    if (tx.gas_limit_wide > env.gas_limit) return .{ .invalid = "gas limit exceeds block gas allowance" };
    const gas_limit: u64 = std.math.cast(u64, tx.gas_limit_wide) orelse
        return .{ .invalid = "gas limit exceeds block gas allowance" };

    const intrinsic = intrinsicGas(tx.data, is_creation, tx.access_list);
    if (gas_limit < intrinsic) return .{ .invalid = "intrinsic gas exceeds gas limit" };

    if (is_creation and tx.data.len > MAX_INITCODE_SIZE) return .{ .invalid = "initcode size exceeded" };

    const sender = try state.getOrCreate(declared.sender);
    if (sender.code.len != 0) return .{ .invalid = "sender is not an EOA" };
    if (sender.nonce != declared.nonce) return .{ .invalid = "nonce mismatch" };
    if (declared.nonce == std.math.maxInt(u64)) return .{ .invalid = "nonce is at maximum" };

    // Effective gas price: YP (66)-(68). Legacy transactions express their
    // whole price in gasPrice; EIP-1559 ones bound base and priority fees.
    var max_charged: u256 = undefined;
    var effective_price: u256 = undefined;
    if (declared.gas_price) |price| {
        if (price < env.base_fee) return .{ .invalid = "gas price below base fee" };
        max_charged = price;
        effective_price = price;
    } else if (declared.max_fee_per_gas) |max_fee| {
        const max_priority = declared.max_priority_fee_per_gas orelse 0;
        if (max_priority > max_fee) return .{ .invalid = "priority fee greater than max fee" };
        if (max_fee < env.base_fee) return .{ .invalid = "max fee below base fee" };
        max_charged = max_fee;
        effective_price = @min(max_priority, max_fee - env.base_fee) + env.base_fee;
    } else {
        return .{ .invalid = "transaction declares no gas price" };
    }

    const max_gas_fee = std.math.mul(u256, max_charged, gas_limit) catch
        return .{ .invalid = "gas limit and price product overflows" };
    const required_balance = std.math.add(u256, max_gas_fee, tx.value) catch
        return .{ .invalid = "required balance overflows" };
    if (sender.balance < required_balance) return .{ .invalid = "insufficient account funds" };

    // ////////////////////////////////////////////////////////////////////////
    // //////////////// Irrevocable transaction cost: gas purchase and nonce.

    sender.balance -= effective_price * gas_limit;
    sender.nonce += 1;

    // Changes from here on revert if execution fails.
    const snapshot = try state.clone();

    const target: Address = if (declared.to) |to|
        to
    else
        createdAddress(alloc, declared.sender, declared.nonce) catch return error.OutOfMemory;

    var gas_left: u64 = gas_limit - intrinsic;
    var success = true;

    const execution: ExecutionResult = blk: {
        if (is_creation) {
            // Creation collision (existing nonce or code): exceptional halt.
            // Ref: YP (89).
            if (state.get(target)) |existing| {
                if (existing.nonce != 0 or existing.code.len != 0) {
                    break :blk .{ .halt = {} };
                }
            }

            // NB: deduct from the sender before taking the created-account
            // pointer; getOrCreate may rehash and invalidate prior pointers.
            (try state.getOrCreate(declared.sender)).balance -= tx.value;

            const created = try state.getOrCreate(target);
            created.nonce = 1; // EIP-161.
            created.balance += tx.value;

            break :blk runEvm(alloc, state, case, .{
                .sender = declared.sender,
                .target = target,
                .value = tx.value,
                .gas = gas_left,
                .effective_price = effective_price,
                .code = tx.data,
                .data = &.{},
            });
        }

        // Precompiled contracts have no code in the state; executing them
        // requires the precompile implementations (Cancun: 0x01 to 0x0a).
        if (target >= 0x01 and target <= 0x0a) {
            return .{ .skipped = .precompile_unsupported };
        }

        (try state.getOrCreate(declared.sender)).balance -= tx.value;
        try state.addBalance(target, tx.value);

        const code = if (state.get(target)) |account| account.code else &[_]u8{};
        if (code.len == 0) break :blk .{ .success = .{ .gas_left = gas_left, .output = &.{} } };

        break :blk runEvm(alloc, state, case, .{
            .sender = declared.sender,
            .target = target,
            .value = tx.value,
            .gas = gas_left,
            .effective_price = effective_price,
            .code = code,
            .data = tx.data,
        });
    };

    switch (execution) {
        .success => |result| {
            gas_left = result.gas_left;

            if (is_creation) {
                // Code deposit: G_codedeposit per byte, EIP-3541 (no 0xEF
                // prefix), EIP-170 (size cap). Failure is an exceptional halt.
                const deposit_cost = G_CODE_DEPOSIT * result.output.len;
                const deposit_ok = deposit_cost <= gas_left and
                    result.output.len <= MAX_CODE_SIZE and
                    (result.output.len == 0 or result.output[0] != 0xef);

                if (deposit_ok) {
                    gas_left -= @intCast(deposit_cost);
                    (try state.getOrCreate(target)).code = result.output;
                } else {
                    success = false;
                    gas_left = 0;
                }
            }
        },
        .revert => |result| {
            success = false;
            gas_left = result.gas_left;
        },
        .halt => {
            success = false;
            gas_left = 0;
        },
        .skip => |reason| return .{ .skipped = reason },
    }

    if (!success) {
        // Restore every effect of execution; gas purchase and nonce increment
        // were applied to the snapshot as well so they survive.
        state.accounts = snapshot.accounts;
    }

    // ////////////////////////////////////////////////////////////////////////
    // //////////////// Settlement: gas refund, priority fee, empties cleanup.

    // No SSTORE/SELFDESTRUCT refund counter exists in zevem yet, so the
    // EIP-3529 refund is always zero.
    const gas_used = gas_limit - gas_left;

    try state.addBalance(declared.sender, effective_price * gas_left);

    const priority_fee = effective_price - env.base_fee;
    const coinbase_reward = priority_fee * gas_used;
    if (coinbase_reward != 0) {
        try state.addBalance(env.coinbase, coinbase_reward);
    } else if (state.get(env.coinbase)) |coinbase| {
        // EIP-161: an already-empty coinbase receiving nothing is destroyed.
        if (coinbase.isEmpty()) state.delete(env.coinbase);
    }

    // EIP-161 touched-account cleanup, limited to the accounts this harness
    // can touch (no inner calls happen yet).
    if (success) {
        if (state.get(target)) |account| {
            if (account.isEmpty()) state.delete(target);
        }
    }
    if (state.get(declared.sender)) |account| {
        if (account.isEmpty()) state.delete(declared.sender);
    }

    return .executed;
}

const EvmInvocation = struct {
    sender: Address,
    target: Address,
    value: u256,
    gas: u64,
    effective_price: u256,
    code: []const u8,
    data: []const u8,
};

const ExecutionResult = union(enum) {
    success: struct { gas_left: u64, output: []const u8 },
    revert: struct { gas_left: u64 },
    halt,
    skip: SkipReason,
};

fn runEvm(
    alloc: std.mem.Allocator,
    state: *StateDB,
    case: fixture.TestCase,
    invocation: EvmInvocation,
) ExecutionResult {
    // zevem types gas_price as u64; fixture prices are word sized.
    const gas_price: u64 = std.math.cast(u64, invocation.effective_price) orelse
        return .{ .skip = .harness_limit };

    var env = zevem.DummyEnv{
        .block = .{
            .parent_hash = [_]u8{0} ** 32,
            .beneficiary = case.env.coinbase,
            .number = case.env.number,
            .gas_limit = case.env.gas_limit,
            .timestamp = case.env.timestamp,
            .randao = case.env.random,
            .base_fee = case.env.base_fee,
        },
        .chain_id = case.chain_id,
        .target_balance = state.balanceOf(invocation.target),
    };

    var evm = EVM.init(alloc, &env) catch return .{ .skip = .harness_limit };

    // zevem charges G_transaction itself inside execute(); the full intrinsic
    // cost was already deducted by the caller, so hand it the remaining gas
    // plus the amount it is about to charge.
    evm.execute(.{
        .sender = invocation.sender,
        .target = invocation.target,
        .value = invocation.value,
        .gas = invocation.gas + G_TRANSACTION,
        .gas_price = gas_price,
        .code = invocation.code,
        .data = invocation.data,
    }) catch |err| return switch (err) {
        Exception.Revert => .{ .revert = .{ .gas_left = evm.gas } },
        Exception.NotImplemented => .{ .skip = .evm_unimplemented },
        Exception.Orchestrate => .{ .skip = .evm_orchestrate },
        Exception.OutOfMemory => .{ .skip = .harness_limit },
        // Exceptional halts consume all remaining gas.
        Exception.OutOfGas,
        Exception.InvalidOp,
        Exception.InvalidJumpDestination,
        Exception.StackUnderflow,
        Exception.StackOverflow,
        Exception.Overflow,
        Exception.MemResizeUInt256Overflow,
        => .halt,
    };

    return .{ .success = .{ .gas_left = evm.gas, .output = evm.return_data } };
}

/// Intrinsic gas g_0: YP (64)-(68), Cancun rules.
fn intrinsicGas(data: []const u8, is_creation: bool, access_list: []const fixture.AccessListEntry) u64 {
    var gas: u64 = G_TRANSACTION;

    for (data) |byte| {
        gas += if (byte == 0) G_TXDATA_ZERO else G_TXDATA_NONZERO;
    }

    if (is_creation) {
        gas += G_TXCREATE;
        // EIP-3860 initcode word cost.
        gas += G_INITCODE_WORD * ((data.len + 31) / 32);
    }

    for (access_list) |entry| {
        gas += G_ACCESS_LIST_ADDRESS;
        gas += G_ACCESS_LIST_STORAGE_KEY * entry.storage_keys.len;
    }

    return gas;
}

/// Contract address for a creation transaction: KEC(RLP([sender, nonce]))[12..].
/// Ref: YP (85).
fn createdAddress(alloc: std.mem.Allocator, sender: Address, nonce: u64) !Address {
    var sender_bytes: [20]u8 = undefined;
    std.mem.writeInt(u160, &sender_bytes, sender, .big);

    var payload: std.ArrayListUnmanaged(u8) = .empty;
    try rlp.encodeBytes(alloc, &payload, &sender_bytes);
    try rlp.encodeUint(alloc, &payload, nonce);

    var encoded: std.ArrayListUnmanaged(u8) = .empty;
    try rlp.encodeList(alloc, &encoded, payload.items);

    var hash: [32]u8 = undefined;
    Keccak256.hash(encoded.items, &hash, .{});

    return std.mem.readInt(u160, hash[12..32], .big);
}

/// Compare the harness state against the fixture's expected post state.
/// Returns a human-readable diff on mismatch, null when they agree.
fn diffState(
    alloc: std.mem.Allocator,
    state: *StateDB,
    expected: []const fixture.Account,
) error{OutOfMemory}!?[]const u8 {
    var diff: std.ArrayListUnmanaged(u8) = .empty;
    const writer = diff.writer(alloc);

    var mismatches: usize = 0;
    const mismatch_cap = 8;

    for (expected) |want| {
        if (mismatches >= mismatch_cap) break;

        const got = state.get(want.address) orelse {
            // The fixture sometimes spells out explicitly-empty accounts.
            if (want.nonce == 0 and want.balance == 0 and want.code.len == 0 and want.storage.len == 0) continue;

            try writer.print("account 0x{x:0>40} missing\n", .{want.address});
            mismatches += 1;
            continue;
        };

        if (got.nonce != want.nonce) {
            try writer.print("account 0x{x:0>40}: nonce {d}, want {d}\n", .{ want.address, got.nonce, want.nonce });
            mismatches += 1;
        }
        if (got.balance != want.balance) {
            try writer.print("account 0x{x:0>40}: balance {d}, want {d}\n", .{ want.address, got.balance, want.balance });
            mismatches += 1;
        }
        if (!std.mem.eql(u8, got.code, want.code)) {
            try writer.print("account 0x{x:0>40}: code mismatch ({d} bytes, want {d})\n", .{ want.address, got.code.len, want.code.len });
            mismatches += 1;
        }

        for (want.storage) |slot| {
            const got_value = got.storage.get(slot.key) orelse 0;
            if (got_value != slot.value) {
                try writer.print("account 0x{x:0>40}: storage[0x{x}] = 0x{x}, want 0x{x}\n", .{ want.address, slot.key, got_value, slot.value });
                mismatches += 1;
            }
        }

        // Storage slots we hold that the fixture does not expect.
        var it = got.storage.iterator();
        slots: while (it.next()) |kv| {
            for (want.storage) |slot| {
                if (slot.key == kv.key_ptr.*) continue :slots;
            }
            try writer.print("account 0x{x:0>40}: unexpected storage[0x{x}] = 0x{x}\n", .{ want.address, kv.key_ptr.*, kv.value_ptr.* });
            mismatches += 1;
        }
    }

    // Accounts we hold that the fixture post state does not mention at all.
    var it = state.accounts.iterator();
    accounts: while (it.next()) |kv| {
        if (mismatches >= mismatch_cap) break;
        for (expected) |want| {
            if (want.address == kv.key_ptr.*) continue :accounts;
        }
        try writer.print("unexpected account 0x{x:0>40}\n", .{kv.key_ptr.*});
        mismatches += 1;
    }

    if (mismatches == 0) return null;
    return diff.items;
}

test "created contract address derivation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Well-known vector: sender 0x6ac7ea33f8831ea9dcc53393aaa88b25a785dbf0
    // with nonce 0 creates 0xcd234a471b72ba2f1ccf0a70fcaba648a5eecd8d.
    const created = try createdAddress(
        arena.allocator(),
        0x6ac7ea33f8831ea9dcc53393aaa88b25a785dbf0,
        0,
    );
    try std.testing.expectEqual(0xcd234a471b72ba2f1ccf0a70fcaba648a5eecd8d, created);
}

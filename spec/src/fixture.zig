//! Parser for execution-spec-tests (EEST) state test fixtures.
//!
//! Fixture format reference:
//! https://eest.ethereum.org/main/consuming_tests/state_test/
//!
//! A fixture file is a JSON object of test name to test case. Each test case
//! holds a single pre state and environment plus vectors of transaction
//! parameters (data, gasLimit, value); each post entry selects one combination
//! of those vectors via `indexes` and declares the expected outcome.

const std = @import("std");

pub const Address = u160;

pub const ParseError = error{
    MalformedFixture,
    MalformedHex,
} || std.mem.Allocator.Error;

pub const Env = struct {
    coinbase: Address,
    gas_limit: u64,
    number: u64,
    timestamp: u64,
    base_fee: u64,
    random: [32]u8,
};

pub const StorageSlot = struct {
    key: u256,
    value: u256,
};

pub const Account = struct {
    address: Address,
    nonce: u64,
    balance: u256,
    code: []const u8,
    storage: []const StorageSlot,
};

pub const AccessListEntry = struct {
    address: Address,
    storage_keys: []const u256,
};

pub const Transaction = struct {
    nonce: u64,
    sender: Address,
    /// null is contract creation (fixture `to` of "").
    to: ?Address,
    gas_price: ?u256,
    max_fee_per_gas: ?u256,
    max_priority_fee_per_gas: ?u256,
    gas_limits: []const u256,
    values: []const u256,
    datas: []const []const u8,
    /// One access list per data vector entry, if present.
    access_lists: ?[]const []const AccessListEntry,
    /// Transaction features the harness does not execute; presence downgrades
    /// the test to a skip rather than a parse failure.
    has_blobs: bool,
    has_authorizations: bool,
};

pub const PostEntry = struct {
    hash: [32]u8,
    logs_hash: [32]u8,
    data_index: usize,
    gas_index: usize,
    value_index: usize,
    expect_exception: ?[]const u8,
    state: []const Account,
};

pub const ForkPost = struct {
    fork: []const u8,
    entries: []const PostEntry,
};

pub const TestCase = struct {
    name: []const u8,
    env: Env,
    pre: []const Account,
    transaction: Transaction,
    posts: []const ForkPost,
    chain_id: u64,
};

/// Parse every test case in a fixture file's contents. All results are
/// allocated in `alloc`, which is assumed to be an arena.
pub fn parseSlice(alloc: std.mem.Allocator, bytes: []const u8) ParseError![]TestCase {
    const value = std.json.parseFromSliceLeaky(std.json.Value, alloc, bytes, .{}) catch
        return error.MalformedFixture;

    const tests = objectOf(value) orelse return error.MalformedFixture;

    var cases = std.ArrayListUnmanaged(TestCase).empty;

    var it = tests.iterator();
    while (it.next()) |kv| {
        const case = objectOf(kv.value_ptr.*) orelse return error.MalformedFixture;
        try cases.append(alloc, .{
            .name = kv.key_ptr.*,
            .env = try parseEnv(case.get("env") orelse return error.MalformedFixture),
            .pre = try parseAccounts(alloc, case.get("pre") orelse return error.MalformedFixture),
            .transaction = try parseTransaction(alloc, case.get("transaction") orelse return error.MalformedFixture),
            .posts = try parsePosts(alloc, case.get("post") orelse return error.MalformedFixture),
            .chain_id = try parseChainId(case.get("config")),
        });
    }

    return cases.items;
}

fn parseEnv(value: std.json.Value) ParseError!Env {
    const env = objectOf(value) orelse return error.MalformedFixture;

    return .{
        .coinbase = try hexIntField(env, "currentCoinbase", Address),
        .gas_limit = try hexIntField(env, "currentGasLimit", u64),
        .number = try hexIntField(env, "currentNumber", u64),
        .timestamp = try hexIntField(env, "currentTimestamp", u64),
        // Frontier-filled fixtures predate EIP-1559 and omit the base fee.
        .base_fee = if (env.get("currentBaseFee")) |fee| try hexInt(fee, u64) else 0,
        .random = if (env.get("currentRandom")) |random| try hexHash(random) else [_]u8{0} ** 32,
    };
}

fn parseAccounts(alloc: std.mem.Allocator, value: std.json.Value) ParseError![]Account {
    const accounts = objectOf(value) orelse return error.MalformedFixture;

    var out = std.ArrayListUnmanaged(Account).empty;

    var it = accounts.iterator();
    while (it.next()) |kv| {
        const account = objectOf(kv.value_ptr.*) orelse return error.MalformedFixture;

        var slots = std.ArrayListUnmanaged(StorageSlot).empty;
        if (account.get("storage")) |storage_value| {
            const storage = objectOf(storage_value) orelse return error.MalformedFixture;
            var slot_it = storage.iterator();
            while (slot_it.next()) |slot| {
                try slots.append(alloc, .{
                    .key = try hexIntString(slot.key_ptr.*, u256),
                    .value = try hexInt(slot.value_ptr.*, u256),
                });
            }
        }

        try out.append(alloc, .{
            .address = try hexIntString(kv.key_ptr.*, Address),
            .nonce = try hexIntField(account, "nonce", u64),
            .balance = try hexIntField(account, "balance", u256),
            .code = try hexBytesField(alloc, account, "code"),
            .storage = slots.items,
        });
    }

    return out.items;
}

fn parseTransaction(alloc: std.mem.Allocator, value: std.json.Value) ParseError!Transaction {
    const tx = objectOf(value) orelse return error.MalformedFixture;

    const to_string = stringOf(tx.get("to") orelse return error.MalformedFixture) orelse
        return error.MalformedFixture;

    return .{
        .nonce = try hexIntField(tx, "nonce", u64),
        .sender = try hexIntField(tx, "sender", Address),
        .to = if (to_string.len == 0) null else try hexIntString(to_string, Address),
        .gas_price = if (tx.get("gasPrice")) |price| try hexInt(price, u256) else null,
        .max_fee_per_gas = if (tx.get("maxFeePerGas")) |fee| try hexInt(fee, u256) else null,
        .max_priority_fee_per_gas = if (tx.get("maxPriorityFeePerGas")) |fee| try hexInt(fee, u256) else null,
        .gas_limits = try hexIntArray(alloc, tx.get("gasLimit") orelse return error.MalformedFixture, u256),
        .values = try hexIntArray(alloc, tx.get("value") orelse return error.MalformedFixture, u256),
        .datas = try hexBytesArray(alloc, tx.get("data") orelse return error.MalformedFixture),
        .access_lists = if (tx.get("accessLists")) |lists| try parseAccessLists(alloc, lists) else null,
        .has_blobs = tx.get("blobVersionedHashes") != null or tx.get("maxFeePerBlobGas") != null,
        .has_authorizations = tx.get("authorizationList") != null,
    };
}

fn parseAccessLists(alloc: std.mem.Allocator, value: std.json.Value) ParseError![]const []const AccessListEntry {
    const lists = arrayOf(value) orelse return error.MalformedFixture;

    var out = std.ArrayListUnmanaged([]const AccessListEntry).empty;

    for (lists.items) |list_value| {
        // A null entry means "no access list" for that data index (legacy tx).
        if (list_value == .null) {
            try out.append(alloc, &.{});
            continue;
        }

        const list = arrayOf(list_value) orelse return error.MalformedFixture;

        var entries = std.ArrayListUnmanaged(AccessListEntry).empty;
        for (list.items) |entry_value| {
            const entry = objectOf(entry_value) orelse return error.MalformedFixture;

            var keys = std.ArrayListUnmanaged(u256).empty;
            const storage_keys = arrayOf(entry.get("storageKeys") orelse return error.MalformedFixture) orelse
                return error.MalformedFixture;
            for (storage_keys.items) |key| try keys.append(alloc, try hexInt(key, u256));

            try entries.append(alloc, .{
                .address = try hexIntField(entry, "address", Address),
                .storage_keys = keys.items,
            });
        }

        try out.append(alloc, entries.items);
    }

    return out.items;
}

fn parsePosts(alloc: std.mem.Allocator, value: std.json.Value) ParseError![]ForkPost {
    const posts = objectOf(value) orelse return error.MalformedFixture;

    var out = std.ArrayListUnmanaged(ForkPost).empty;

    var it = posts.iterator();
    while (it.next()) |kv| {
        const entries_value = arrayOf(kv.value_ptr.*) orelse return error.MalformedFixture;

        var entries = std.ArrayListUnmanaged(PostEntry).empty;
        for (entries_value.items) |entry_value| {
            const entry = objectOf(entry_value) orelse return error.MalformedFixture;
            const indexes = objectOf(entry.get("indexes") orelse return error.MalformedFixture) orelse
                return error.MalformedFixture;

            try entries.append(alloc, .{
                .hash = try hexHash(entry.get("hash") orelse return error.MalformedFixture),
                .logs_hash = try hexHash(entry.get("logs") orelse return error.MalformedFixture),
                .data_index = try indexField(indexes, "data"),
                .gas_index = try indexField(indexes, "gas"),
                .value_index = try indexField(indexes, "value"),
                .expect_exception = if (entry.get("expectException")) |exception|
                    stringOf(exception) orelse return error.MalformedFixture
                else
                    null,
                .state = try parseAccounts(alloc, entry.get("state") orelse return error.MalformedFixture),
            });
        }

        try out.append(alloc, .{ .fork = kv.key_ptr.*, .entries = entries.items });
    }

    return out.items;
}

fn parseChainId(value: ?std.json.Value) ParseError!u64 {
    const config = objectOf(value orelse return 1) orelse return error.MalformedFixture;
    const chain_id = config.get("chainid") orelse return 1;
    return hexInt(chain_id, u64);
}

// ////////////////////////////////////////////////////////////////////////////
// //////////////// JSON value navigation and hex parsing.

fn objectOf(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) {
        .object => |object| object,
        else => null,
    };
}

fn arrayOf(value: std.json.Value) ?std.json.Array {
    return switch (value) {
        .array => |array| array,
        else => null,
    };
}

fn stringOf(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |string| string,
        else => null,
    };
}

fn stripHexPrefix(string: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, string, "0x")) string[2..] else string;
}

fn hexIntString(string: []const u8, comptime T: type) ParseError!T {
    const digits = stripHexPrefix(string);
    if (digits.len == 0) return 0;
    return std.fmt.parseInt(T, digits, 16) catch error.MalformedHex;
}

fn hexInt(value: std.json.Value, comptime T: type) ParseError!T {
    return hexIntString(stringOf(value) orelse return error.MalformedFixture, T);
}

fn hexIntField(object: std.json.ObjectMap, field: []const u8, comptime T: type) ParseError!T {
    return hexInt(object.get(field) orelse return error.MalformedFixture, T);
}

fn hexIntArray(alloc: std.mem.Allocator, value: std.json.Value, comptime T: type) ParseError![]T {
    const array = arrayOf(value) orelse return error.MalformedFixture;

    const out = try alloc.alloc(T, array.items.len);
    for (array.items, 0..) |item, i| out[i] = try hexInt(item, T);
    return out;
}

fn hexBytesString(alloc: std.mem.Allocator, string: []const u8) ParseError![]u8 {
    const digits = stripHexPrefix(string);
    if (digits.len % 2 != 0) return error.MalformedHex;

    const out = try alloc.alloc(u8, digits.len / 2);
    _ = std.fmt.hexToBytes(out, digits) catch return error.MalformedHex;
    return out;
}

fn hexBytesField(alloc: std.mem.Allocator, object: std.json.ObjectMap, field: []const u8) ParseError![]u8 {
    const value = object.get(field) orelse return error.MalformedFixture;
    return hexBytesString(alloc, stringOf(value) orelse return error.MalformedFixture);
}

fn hexBytesArray(alloc: std.mem.Allocator, value: std.json.Value) ParseError![]const []const u8 {
    const array = arrayOf(value) orelse return error.MalformedFixture;

    const out = try alloc.alloc([]const u8, array.items.len);
    for (array.items, 0..) |item, i| {
        out[i] = try hexBytesString(alloc, stringOf(item) orelse return error.MalformedFixture);
    }
    return out;
}

/// Hash fields are parsed as integers then re-serialised so that short or
/// unpadded hex (e.g. "0x00") still lands in a [32]u8 correctly.
fn hexHash(value: std.json.Value) ParseError![32]u8 {
    const parsed = try hexInt(value, u256);
    var out: [32]u8 = undefined;
    std.mem.writeInt(u256, &out, parsed, .big);
    return out;
}

fn indexField(object: std.json.ObjectMap, field: []const u8) ParseError!usize {
    const value = object.get(field) orelse return error.MalformedFixture;
    return switch (value) {
        .integer => |integer| if (integer < 0) error.MalformedFixture else @intCast(integer),
        else => error.MalformedFixture,
    };
}

test "parse a minimal fixture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const fixture =
        \\{
        \\ "tests/some_test.py::test_thing[fork_Cancun-state_test]": {
        \\  "env": {
        \\   "currentCoinbase": "0x2adc25665018aa1fe0e6bc666dac8fc2697ff9ba",
        \\   "currentGasLimit": "0x07270e00",
        \\   "currentNumber": "0x01",
        \\   "currentTimestamp": "0x03e8",
        \\   "currentRandom": "0x00",
        \\   "currentBaseFee": "0x07"
        \\  },
        \\  "pre": {
        \\   "0x0a16f360235334164b5f50ca2fa0d37e420cedb8": {
        \\    "nonce": "0x00",
        \\    "balance": "0x3635c9adc5dea00000",
        \\    "code": "0x",
        \\    "storage": { "0x01": "0x02" }
        \\   }
        \\  },
        \\  "transaction": {
        \\   "nonce": "0x00",
        \\   "gasPrice": "0x0a",
        \\   "gasLimit": ["0x0f4240"],
        \\   "value": ["0x00"],
        \\   "data": ["0x600100"],
        \\   "sender": "0x0a16f360235334164b5f50ca2fa0d37e420cedb8",
        \\   "to": ""
        \\  },
        \\  "post": {
        \\   "Cancun": [
        \\    {
        \\     "hash": "0xdfe3e551e5a9ad38d8e078915698609e11a4fdd5fd4c0db4213a4532ab34ccee",
        \\     "logs": "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
        \\     "txbytes": "0x00",
        \\     "indexes": { "data": 0, "gas": 0, "value": 0 },
        \\     "state": {}
        \\    }
        \\   ]
        \\  },
        \\  "config": { "chainid": "0x01" }
        \\ }
        \\}
    ;

    const cases = try parseSlice(arena.allocator(), fixture);
    try std.testing.expectEqual(1, cases.len);

    const case = cases[0];
    try std.testing.expectEqual(0x2adc25665018aa1fe0e6bc666dac8fc2697ff9ba, case.env.coinbase);
    try std.testing.expectEqual(7, case.env.base_fee);
    try std.testing.expectEqual(1, case.pre.len);
    try std.testing.expectEqual(1, case.pre[0].storage.len);
    try std.testing.expectEqual(2, case.pre[0].storage[0].value);
    try std.testing.expectEqual(null, case.transaction.to);
    try std.testing.expectEqual(10, case.transaction.gas_price.?);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x60, 0x01, 0x00 }, case.transaction.datas[0]);
    try std.testing.expectEqual(1, case.posts.len);
    try std.testing.expectEqualStrings("Cancun", case.posts[0].fork);
    try std.testing.expectEqual(null, case.posts[0].entries[0].expect_exception);
    try std.testing.expectEqual(1, case.chain_id);
}

//! Merkle Patricia Trie root computation, used to verify post-state roots from
//! specification test fixtures. Only root computation over a known key/value
//! set is implemented; there is no node storage, proof generation, or deletion.
//!
//! Keys given to `secureRoot` are hashed with Keccak-256 first ("secure" trie),
//! which is how both the world state trie and account storage tries key their
//! content.
//!
//! Ref: YP Appendix D.

const std = @import("std");
const Keccak256 = std.crypto.hash.sha3.Keccak256;

const rlp = @import("rlp.zig");

const Bytes = std.ArrayListUnmanaged(u8);

/// Keccak-256 of the RLP empty string (0x80); root of the empty trie.
pub const EMPTY_ROOT = [32]u8{
    0x56, 0xe8, 0x1f, 0x17, 0x1b, 0xcc, 0x55, 0xa6, 0xff, 0x83, 0x45, 0xe6, 0x92, 0xc0, 0xf8, 0x6e,
    0x5b, 0x48, 0xe0, 0x1b, 0x99, 0x6c, 0xad, 0xc0, 0x01, 0x62, 0x2f, 0xb5, 0xe3, 0x63, 0xb4, 0x21,
};

/// Keccak-256 of the RLP empty byte string; code hash of a codeless account.
pub const EMPTY_CODE_HASH = [32]u8{
    0xc5, 0xd2, 0x46, 0x01, 0x86, 0xf7, 0x23, 0x3c, 0x92, 0x7e, 0x7d, 0xb2, 0xdc, 0xc7, 0x03, 0xc0,
    0xe5, 0x00, 0xb6, 0x53, 0xca, 0x82, 0x27, 0x3b, 0x7b, 0xfa, 0xd8, 0x04, 0x5d, 0x85, 0xa4, 0x70,
};

/// One trie entry. `key` is the raw (pre-hash) key; `value` must already be
/// RLP-encoded.
pub const Pair = struct {
    key: []const u8,
    value: []const u8,
};

/// Compute the root of a secure trie containing `pairs`. Allocation is assumed
/// to be arena-backed; nothing is individually freed.
pub fn secureRoot(alloc: std.mem.Allocator, pairs: []const Pair) ![32]u8 {
    if (pairs.len == 0) return EMPTY_ROOT;

    // Secure trie: actual trie keys are the Keccak-256 hashes of the given
    // keys, expanded to nibbles (so always 64 nibbles long here).
    const entries = try alloc.alloc(Entry, pairs.len);
    for (pairs, 0..) |pair, i| {
        var hashed: [32]u8 = undefined;
        Keccak256.hash(pair.key, &hashed, .{});

        const nibbles = try alloc.alloc(u4, 64);
        for (hashed, 0..) |byte, j| {
            nibbles[2 * j] = @intCast(byte >> 4);
            nibbles[2 * j + 1] = @intCast(byte & 0x0f);
        }

        entries[i] = .{ .nibbles = nibbles, .value = pair.value };
    }

    std.mem.sort(Entry, entries, {}, Entry.lessThan);

    // Hashed keys are unique unless the caller passed duplicate keys.
    for (entries[1..], 0..) |entry, i| {
        std.debug.assert(!std.mem.eql(u4, entry.nibbles, entries[i].nibbles));
    }

    const node = try encodeNode(alloc, entries, 0);

    var root: [32]u8 = undefined;
    Keccak256.hash(node, &root, .{});
    return root;
}

const Entry = struct {
    nibbles: []const u4,
    value: []const u8,

    fn lessThan(_: void, a: Entry, b: Entry) bool {
        return std.mem.lessThan(u4, a.nibbles, b.nibbles);
    }
};

/// Returns the RLP encoding of the node containing `entries`, all of which
/// share their first `depth` nibbles. `entries` must be sorted and non-empty.
fn encodeNode(alloc: std.mem.Allocator, entries: []const Entry, depth: usize) ![]const u8 {
    std.debug.assert(entries.len > 0);

    // Leaf node: [HP(remaining path, leaf), value]
    if (entries.len == 1) {
        const entry = entries[0];

        var payload: Bytes = .empty;
        try rlp.encodeBytes(alloc, &payload, try hexPrefix(alloc, entry.nibbles[depth..], true));
        try rlp.encodeBytes(alloc, &payload, entry.value);

        var node: Bytes = .empty;
        try rlp.encodeList(alloc, &node, payload.items);
        return node.items;
    }

    // Find the longest prefix (from depth) common to all entries. Since
    // entries are sorted it suffices to compare the first against the last.
    const first = entries[0].nibbles;
    const last = entries[entries.len - 1].nibbles;

    var common: usize = 0;
    while (depth + common < first.len and first[depth + common] == last[depth + common]) common += 1;

    // Extension node: [HP(common path, not-leaf), child reference]
    if (common > 0) {
        const child = try encodeNode(alloc, entries, depth + common);

        var payload: Bytes = .empty;
        try rlp.encodeBytes(alloc, &payload, try hexPrefix(alloc, first[depth .. depth + common], false));
        try appendReference(alloc, &payload, child);

        var node: Bytes = .empty;
        try rlp.encodeList(alloc, &node, payload.items);
        return node.items;
    }

    // Branch node: [child 0, ..., child 15, value]
    var payload: Bytes = .empty;

    var start: usize = 0;
    for (0..16) |nibble| {
        var end = start;
        while (end < entries.len and entries[end].nibbles[depth] == nibble) end += 1;

        if (end == start) {
            try payload.append(alloc, 0x80); // Empty child slot.
        } else {
            const child = try encodeNode(alloc, entries[start..end], depth + 1);
            try appendReference(alloc, &payload, child);
        }

        start = end;
    }

    // Secure-trie keys all have equal (64 nibble) length so no key can
    // terminate at a branch; the value slot is always empty.
    try payload.append(alloc, 0x80);

    var node: Bytes = .empty;
    try rlp.encodeList(alloc, &node, payload.items);
    return node.items;
}

/// Append a child node reference: nodes whose RLP is at least 32 bytes are
/// referenced by hash, shorter nodes are embedded directly.
fn appendReference(alloc: std.mem.Allocator, out: *Bytes, node: []const u8) !void {
    if (node.len >= 32) {
        var hash: [32]u8 = undefined;
        Keccak256.hash(node, &hash, .{});
        try rlp.encodeBytes(alloc, out, &hash);
    } else {
        try out.appendSlice(alloc, node);
    }
}

/// Hex-prefix encode a nibble path: flag bit 2 marks a leaf, bit 1 odd length.
/// Ref: YP Appendix C.
fn hexPrefix(alloc: std.mem.Allocator, nibbles: []const u4, leaf: bool) ![]const u8 {
    const flag: u8 = if (leaf) 2 else 0;
    const odd = nibbles.len % 2 == 1;

    const out = try alloc.alloc(u8, 1 + nibbles.len / 2);

    var i: usize = 0;
    if (odd) {
        out[0] = (flag + 1) << 4 | nibbles[0];
        i = 1;
    } else {
        out[0] = flag << 4;
    }

    var j: usize = 1;
    while (i < nibbles.len) : ({
        i += 2;
        j += 1;
    }) {
        out[j] = @as(u8, nibbles[i]) << 4 | nibbles[i + 1];
    }

    return out;
}

test "empty trie root constant" {
    // EMPTY_ROOT must be the hash of the RLP empty string.
    var hash: [32]u8 = undefined;
    Keccak256.hash(&[_]u8{0x80}, &hash, .{});
    try std.testing.expectEqualSlices(u8, &EMPTY_ROOT, &hash);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(EMPTY_ROOT, try secureRoot(arena.allocator(), &.{}));
}

test "empty code hash constant" {
    var hash: [32]u8 = undefined;
    Keccak256.hash(&[_]u8{}, &hash, .{});
    try std.testing.expectEqualSlices(u8, &EMPTY_CODE_HASH, &hash);
}

test "hex-prefix encoding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Examples from YP Appendix C.
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x11, 0x23, 0x45 }, try hexPrefix(alloc, &[_]u4{ 1, 2, 3, 4, 5 }, false));
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x01, 0x23, 0x45 }, try hexPrefix(alloc, &[_]u4{ 0, 1, 2, 3, 4, 5 }, false));
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x20, 0x0f, 0x1c, 0xb8 }, try hexPrefix(alloc, &[_]u4{ 0, 0xf, 1, 0xc, 0xb, 8 }, true));
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x3f, 0x1c, 0xb8 }, try hexPrefix(alloc, &[_]u4{ 0xf, 1, 0xc, 0xb, 8 }, true));
}

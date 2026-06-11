//! Minimal RLP encoding, only what the spec harness needs (account bodies, trie
//! nodes, storage values). Decoding is intentionally absent.
//!
//! Ref: YP Appendix B.

const std = @import("std");

const Bytes = std.ArrayListUnmanaged(u8);

/// Encode a byte string per RLP rules, appending to `out`.
pub fn encodeBytes(alloc: std.mem.Allocator, out: *Bytes, bytes: []const u8) !void {
    if (bytes.len == 1 and bytes[0] < 0x80) {
        try out.append(alloc, bytes[0]);
        return;
    }

    try encodeLength(alloc, out, 0x80, bytes.len);
    try out.appendSlice(alloc, bytes);
}

/// Encode an unsigned integer as its minimal big-endian byte string (no leading
/// zeroes; zero is the empty string) per RLP rules, appending to `out`.
pub fn encodeUint(alloc: std.mem.Allocator, out: *Bytes, value: u256) !void {
    var buf: [32]u8 = undefined;
    std.mem.writeInt(u256, &buf, value, .big);

    const minimal = stripLeadingZeroes(&buf);
    try encodeBytes(alloc, out, minimal);
}

/// Wrap an already RLP-encoded payload (a concatenation of encoded items) as a
/// list, appending to `out`.
pub fn encodeList(alloc: std.mem.Allocator, out: *Bytes, payload: []const u8) !void {
    try encodeLength(alloc, out, 0xc0, payload.len);
    try out.appendSlice(alloc, payload);
}

/// Strips leading zero bytes; the all-zero input collapses to the empty slice.
pub fn stripLeadingZeroes(bytes: []const u8) []const u8 {
    var start: usize = 0;
    while (start < bytes.len and bytes[start] == 0) start += 1;
    return bytes[start..];
}

fn encodeLength(alloc: std.mem.Allocator, out: *Bytes, base: u8, length: usize) !void {
    if (length < 56) {
        try out.append(alloc, base + @as(u8, @intCast(length)));
        return;
    }

    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, length, .big);
    const minimal = stripLeadingZeroes(&buf);

    try out.append(alloc, base + 55 + @as(u8, @intCast(minimal.len)));
    try out.appendSlice(alloc, minimal);
}

test "rlp byte string forms" {
    const alloc = std.testing.allocator;

    // Single byte below 0x80 encodes as itself.
    var a: Bytes = .empty;
    defer a.deinit(alloc);
    try encodeBytes(alloc, &a, &[_]u8{0x7f});
    try std.testing.expectEqualSlices(u8, &[_]u8{0x7f}, a.items);

    // Empty string is 0x80.
    var b: Bytes = .empty;
    defer b.deinit(alloc);
    try encodeBytes(alloc, &b, &[_]u8{});
    try std.testing.expectEqualSlices(u8, &[_]u8{0x80}, b.items);

    // "dog" is 0x83 'd' 'o' 'g'.
    var c: Bytes = .empty;
    defer c.deinit(alloc);
    try encodeBytes(alloc, &c, "dog");
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x83, 'd', 'o', 'g' }, c.items);

    // 56-byte string takes the long form: 0xb8 0x38 ...
    var d: Bytes = .empty;
    defer d.deinit(alloc);
    try encodeBytes(alloc, &d, "a" ** 56);
    try std.testing.expectEqual(0xb8, d.items[0]);
    try std.testing.expectEqual(0x38, d.items[1]);
    try std.testing.expectEqual(58, d.items.len);
}

test "rlp integers" {
    const alloc = std.testing.allocator;

    // Zero is the empty string.
    var a: Bytes = .empty;
    defer a.deinit(alloc);
    try encodeUint(alloc, &a, 0);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x80}, a.items);

    // 15 is a single byte.
    var b: Bytes = .empty;
    defer b.deinit(alloc);
    try encodeUint(alloc, &b, 15);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x0f}, b.items);

    // 1024 is 0x82 0x04 0x00.
    var c: Bytes = .empty;
    defer c.deinit(alloc);
    try encodeUint(alloc, &c, 1024);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x82, 0x04, 0x00 }, c.items);
}

test "rlp lists" {
    const alloc = std.testing.allocator;

    // Empty list is 0xc0.
    var a: Bytes = .empty;
    defer a.deinit(alloc);
    try encodeList(alloc, &a, &[_]u8{});
    try std.testing.expectEqualSlices(u8, &[_]u8{0xc0}, a.items);

    // ["cat", "dog"] is 0xc8 0x83 'c' 'a' 't' 0x83 'd' 'o' 'g'.
    var payload: Bytes = .empty;
    defer payload.deinit(alloc);
    try encodeBytes(alloc, &payload, "cat");
    try encodeBytes(alloc, &payload, "dog");

    var b: Bytes = .empty;
    defer b.deinit(alloc);
    try encodeList(alloc, &b, payload.items);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xc8, 0x83, 'c', 'a', 't', 0x83, 'd', 'o', 'g' }, b.items);
}

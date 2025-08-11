//! Provides easy access to types an EVM needs to function correctly.

pub const Word = u256;
pub const DoubleWord = u512;
pub const SignedWord = i256;

// XXX: [20]u8 would represent this better but then we need to parseInt convert to/from the
//      array of bytes.
pub const Address = u160;

pub const Hash32 = [32]u8;
pub const Bytes32 = [32]u8;

// TODO: Comptime `Bytes` function which takes comptime in and returns an array
//       of that size? so `Bytes(32)` for [32]u8 and `Bytes(20)` for [20]u8?

/// Blocks.
pub const BlockHeader = @import("types/BlockHeader.zig");

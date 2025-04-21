//! Provides easy access to types an EVM needs to function correctly.

pub const Word = u256;
pub const DoubleWord = u512;
pub const SignedWord = i256;

// TODO: Or [20]u8?
pub const Address = u160;

/// Blocks.
pub const BlockHeader = @import("types/BlockHeader.zig");

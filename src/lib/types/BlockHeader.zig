//! Block header information relevant to EVM execution.
//! I subscript H in the YellowPaper (I_H).
const types = @import("../types.zig");

const BlockHeader = @This();

/// Current block's parent's header Keccak-256 hash: I_H_p
parent_hash: types.Hash32,

/// Current block's beneficiary (coinbase) address: I_H_c
beneficiary: types.Address,

/// Current block's number: I_H_i
number: u64,

/// Current block's gas limit: I_H_l
gas_limit: u64,

/// Current block's timestamp: I_H_s
timestamp: u64,

/// Current block's RANDAO mix: I_H_a
randao: types.Bytes32, // TODO: Bytes32 is the proper type right?

/// Current block's base fee: I_H_f
base_fee: u64, // TODO: Bigger type since denominated in Wei and can overflow a u64

// Decl literals for easier initialisation.
pub const default: BlockHeader = .{
    // TODO: Reasonable default values for this.
    .parent_hash = [_]u8{0} ** 32,
    .beneficiary = 0,
    .number = 0,
    .gas_limit = 30_000_000, // Arbitrary.
    .timestamp = 4,
    .randao = [_]u8{0} ** 32,
    .base_fee = 6,
};

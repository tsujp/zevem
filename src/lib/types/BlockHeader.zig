//! Block header information relevant to EVM execution.
//! I subscript H in the YellowPaper (I_H).
const types = @import("../types.zig");

const BlockHeader = @This();

/// Current block's parent's header Keccak-256 hash: I_H_p
parent_hash: u8, // TODO: Proper type.

/// Current block's beneficiary (coinbase) address: I_H_c
beneficiary: types.Address,

/// Current block's number: I_H_i
number: u256,

/// Current block's gas limit: I_H_l
gas_limit: u8, // TODO: Proper type.

/// Current block's timestamp: I_H_s
timestamp: u8, // TODO: Proper type.

/// Current block's RANDAO mix: I_H_a
randao: u8, // TODO: Proper type.

/// Current block's base fee: I_H_f
base_fee: u8, // TODO: Proper type.

// Decl literals for easier initialisation.
pub const default: BlockHeader = .{
    // TODO: Reasonable default values for this.
    .parent_hash = 1,
    .beneficiary = 2,
    .number = 0,
    .gas_limit = 3,
    .timestamp = 4,
    .randao = 5,
    .base_fee = 6,
};

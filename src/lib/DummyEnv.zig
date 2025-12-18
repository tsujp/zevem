const types = @import("types.zig");

const DummyEnv = @This();

// TODO: Or as function pointers so we can namespace the block header stuff under `block`?

/// Block header information the EVM requires.
block: types.BlockHeader,

/// ChainID: β
chain_id: u64, // TODO: Does it really need to be u256?

// TODO: API design here, is this fine? What about as execution progresses?
/// Balance of current EVM target I_a: σ[I_a]_b
target_balance: u256,

// Decl literals for easier initialisation.
pub const default: DummyEnv = .{
    .block = .default,
    .chain_id = 0,
    .target_balance = 0,
};
// pub fn init(block: types.BlockHeader) DummyEnv {
//     return .{ .block = block };
// }

pub fn getBalance(_: *DummyEnv) !u256 {
    return 0;
}

// // /////////////////////////////////////////////////////////////////////////////
// // //////////////// Block header information relevant to EVM execution.
// // //////////////// I subscript H in the YellowPaper (I_H).

// // The return values of these functions serve as default values, DummyEnv should not be used
// //   in production of course.

// /// Current block's parent's header Keccak-256 hash: I_H_p
// pub fn getBlockParentHash(_: *DummyEnv) !types.Hash32 {
//     return [_]u8{0} ** 32;
// }
// // parent_hash: types.Hash32,

// /// Current block's beneficiary (coinbase) address: I_H_c
// pub fn getBlockBeneficiary(_: *DummyEnv) !types.Address {
//     return 0;
// }
// // beneficiary: types.Address,

// /// Current block's number: I_H_i
// pub fn getBlockNumber(_: *DummyEnv) !u64 {
//     return 0;
// }
// // number: u64,

// /// Current block's gas limit: I_H_l
// pub fn getBlockGasLimit(_: *DummyEnv) !u64 {
//     return 30_000_000; // Arbitrary.
// }
// // gas_limit: u64,

// /// Current block's timestamp: I_H_s
// pub fn getBlockTimestamp(_: *DummyEnv) !u64 {
//     return 0;
// }
// // timestamp: u64,

// /// Current block's RANDAO mix: I_H_a
// pub fn getBlockRandao(_: *DummyEnv) !types.Bytes32 {
//     return [_]u8{0} ** 32;
// }
// // randao: types.Bytes32, // TODO: Bytes32 is the proper type right?

// /// Current block's base fee: I_H_f
// pub fn getBlockBaseFee(_: *DummyEnv) !u64 {
//     // TODO: Some default.
//     return 69;
// }
// // base_fee: u64, // TODO: Bigger type since denominated in Wei and can overflow a u64

const types = @import("types.zig");

const DummyEnv = @This();

// TODO: Rename to block_header for extra clarity?
/// Block header information the EVM requires.
block: types.BlockHeader,

// Decl literals for easier initialisation.
pub const default: DummyEnv = .{ .block = .default };
pub fn init(block: types.BlockHeader) DummyEnv {
    return .{ .block = block };
}

pub fn getBalance(_: *DummyEnv, _: u256) !u256 {
    return 0;
}

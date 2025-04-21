const DummyEnv = @This();

// TODO: Zig convention states unless this file has top-level fields it should be snake case. Once environment stuff fleshed out rename as appropriate.

pub fn getBalance(_: *DummyEnv, _: u256) !u256 {
    return 0;
}

// TODO: This could be it's own DummyBlock.zig, also passed in when creating a new EVM or it be a struct parameter to execute() or even just fields on DummyEnv or a struct on DummyEnv field 'block' etc. For now it feels like it should be part of a unified "environment" hence being here.

/// Block header information relevant to EVM.
// I subscript H in YellowPaper.

/// Current block's parent's header Keccak-256 hash: I_H_p
pub fn getParentHash(_: *DummyEnv) !u8 {
    // TODO: KEC256 hash return.
    return 0;
}

/// Current block's beneficiary (coinbase) address: I_H_c
pub fn getBeneficiary(_: *DummyEnv) !u8 {
    // TODO: 160-bit address return.
    return 0;
}

/// Current block's number: I_H_i
pub fn getNumber(_: *DummyEnv) !u256 {
    return 0;
}

/// Current block's gas limit: I_H_l
pub fn getGasLimit(_: *DummyEnv) !u8 {
    // TODO: What value should be stubbed here?
    return 0;
}

/// Current block's timestamp: I_H_s
pub fn getTimestamp(_: *DummyEnv) !u8 {
    // TODO: reasonable unix timestamp.
    return 0;
}

/// Current block's RANDAO mix: I_H_a
pub fn getPrevRandao(_: *DummyEnv) !u8 {
    // TODO: Behaviour in previous forks.
    // TODO: RANDAO mix of previous block.
    return 0;
}

/// Current block's base fee: I_H_f
pub fn getBaseFeePerGas(_: *DummyEnv) !u8 {
    // TODO: block base fee.
    return 0;
}

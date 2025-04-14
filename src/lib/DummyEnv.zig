const DummyEnv = @This();

// TODO: Zig convention states unless this file has top-level fields it should be snake case. Once environment stuff fleshed out rename as appropriate.

pub fn getBalance(_: *DummyEnv, _: u256) !u256 {
    return 0;
}

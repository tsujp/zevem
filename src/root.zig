//! Library (zevem) root.

const std = @import("std");
const builtin = @import("builtin");

pub const evm = @import("lib/evm.zig");
pub const DummyEnv = @import("lib/DummyEnv.zig");

pub const EVM = evm.New(DummyEnv);

// TODO: test-filter now works as expected. It looks like under the old setup before this commit that test filter broke after lib.test. but im unsure why that would be the case. Try and get a minimal reproduction to see what the issue is and report the bug.

pub const utils = struct {
    /// Compile-time hex-to-bytes.
    pub fn htb(comptime bytes: []const u8) [bytes.len / 2]u8 {
        // Inspired by: https://github.com/jsign/phant/blob/18eeadffd24de9c6b3ae5c7505ada52c43f2b1d4/src/common/hexutils.zig#L73
        comptime var buf: [bytes.len / 2]u8 = undefined;
        _ = comptime std.fmt.hexToBytes(&buf, bytes) catch @compileError("hex-to-bytes error");
        return buf;
    }
};

test {
    std.testing.refAllDeclsRecursive(@This());

    // Tests under lib/test are for convenience as they include a lot of cases.
    _ = @import("lib/test/opcode.zig");
    _ = @import("lib/test/gas.zig");
}

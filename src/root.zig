//! Library (zevem) root.

const std = @import("std");
const builtin = @import("builtin");

pub const evm = @import("lib/evm.zig");
pub const DummyEnv = @import("lib/DummyEnv.zig");

pub const EVM = evm.New(DummyEnv);
pub const config = @import("config");

// TODO: Since moving stackOffTop into utils the imports (like this one) feel a bit messy? Clean up later?
const types = @import("lib/types.zig");

// TODO: test-filter now works as expected. It looks like under the old setup before this commit that test filter broke after lib.test. but im unsure why that would be the case. Try and get a minimal reproduction to see what the issue is and report the bug.

pub const utils = struct {
    /// Compile-time hex-to-bytes.
    pub fn htb(comptime bytes: []const u8) [bytes.len / 2]u8 {
        // Inspired by: https://github.com/jsign/phant/blob/18eeadffd24de9c6b3ae5c7505ada52c43f2b1d4/src/common/hexutils.zig#L73
        comptime var buf: [bytes.len / 2]u8 = undefined;
        _ = comptime std.fmt.hexToBytes(&buf, bytes) catch @compileError("hex-to-bytes error");
        return buf;
    }

    // TODO: u10 somewhat arbitrary, max stack length is 1024 and 2^10 = 1024. Is being this specific on parameter value here fine?
    pub fn stackOffTop(self: *EVM, index: u10) types.Word {
        // TODO: Do we need assert here, double check if Zig gives us bounds checking for free on _runtime_ slice values (BoundedArray.get accesses the backing slice by index). I don't think we do, only for comptime known.
        return self.stack.get(self.stack.len - index - 1);
    }
};

test {
    std.testing.refAllDeclsRecursive(@This());

    // Tests under lib/test are for convenience as they include a lot of cases.
    _ = @import("lib/test/opcode.zig");
    _ = @import("lib/test/gas.zig");
}

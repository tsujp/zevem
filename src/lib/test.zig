const std = @import("std");

test "tests" {
    // TODO: Scoped debug log levels later.
    std.testing.log_level = .debug;

    std.testing.refAllDeclsRecursive(@import("test/opcode.test.zig"));
}

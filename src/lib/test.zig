const std = @import("std");

test "tests" {
    std.testing.log_level = .debug;

    std.testing.refAllDeclsRecursive(@import("test/opcode.test.zig"));
}

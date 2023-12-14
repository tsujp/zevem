const std = @import("std");
const print = std.debug.print;

const OpCode = enum(u8) {
    Stop = 0x00,
    Add,
    Mul,
};

pub fn main() !void {
    print("Starting\n", .{});

    // TODO: Bytecode will not be this simple.
    const Bytecode = [_]OpCode{ .Add, .Mul, .Add, .Stop };

    var ip: u32 = 0;

    // TODO: VM should be it's own structure.
    while (true) {
        const op = Bytecode[ip];

        print("ip: {d}, op: ({s}, {})\n", .{ ip, @tagName(op), @intFromEnum(op) });

        _ = switch (op) {
            .Stop => {
                print("Halting execution.\n", .{});
                return;
            },
            .Add => {},
            .Mul => {},
        };

        ip += 1;
    }
}

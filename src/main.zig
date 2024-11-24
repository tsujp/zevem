const std = @import("std");
const print = std.debug.print;
const EnumField = std.builtin.Type.EnumField;

// /////////////////////////////////////////////////////////////////////////////
// //////////////// COMPTIME ENUM

// TODO: Move comptime enum stuff elsewhere?
const Op = MakeOpCodes(.{
    .{ "Stop", 0x00 },
    .{"Add"},
    .{ "Mul", 0x05 }, // Not the actual opcode location, just for pretendies.
    .{"Sub"},
    .{"Div"},
    .{"SDiv"},
    .{ "Push0", 0x5F },
    .{ "Push", 0x60, 0x7F },
    .{ "Create", 0xF0 },
    .{ "Call", 0xF1 },
});

// Return enum field value.
pub fn enumField(comptime name: [:0]const u8, comptime value: u8) [1]EnumField {
    return [1]EnumField{.{ .name = name, .value = value }};
}

// Comptime construction of enum with fields over specified ranges.
pub fn MakeOpCodes(comptime defs: anytype) type {
    comptime var fields: []const EnumField = &[_]EnumField{};

    if (@typeInfo(@TypeOf(defs)) != .Struct) {
        @compileError("expected struct (tuple), found " ++ @typeName(@TypeOf(defs)));
    }

    // Tuple `defs` contains N tuples of opcode definitions.
    for (defs) |df| {
        _ = switch (df.len) {
            // Name only, opcode has ordinal +1 of previous.
            1 => {
                fields = fields ++ enumField(df[0], fields[fields.len - 1].value + 1);
            },
            // Name and explicit ordinal, set as given.
            2 => {
                fields = fields ++ enumField(df[0], df[1]);
            },
            // Name and explicit ordinal inclusive range, iterate and set.
            3 => {
                for (df[1]..(df[2] + 1)) |opValue| {
                    const opSuffix = opValue - df[1] + 1;
                    fields = fields ++ enumField(std.fmt.comptimePrint("{s}{d}", .{ df[0], opSuffix }), opValue);
                }
            },
            else => {}, // TODO: An error.
        };
    }

    return @Type(.{
        .Enum = .{
            .tag_type = u8,
            .fields = fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_exhaustive = true,
        },
    });
}
// END -- COMPTIME ENUM.

const MAX_STACK_DEPTH = 1024;
const WORD = u256;

// TODO: From comptime as well?
const Instruction = struct {
    gas: u32,
    desc: []const u8,
};

pub fn defOps(comptime instructions: std.enums.EnumFieldStruct(Op, Instruction, null)) [256]Instruction {
    comptime var ops = std.mem.zeroes([256]Instruction);

    for (std.meta.fields(@TypeOf(instructions))) |inst| {
        const o = @intFromEnum(@field(Op, inst.name));
        const i = @field(instructions, inst.name);

        ops[o] = i;
    }

    return ops;
}

// XXX: This _does_ waste _some_ memory as the EVM does not have opcodes enough
//      to fill 1-byte completely but is constant lookup for the logic per opcode
//      which is more important. Perhaps there's a dense but constant lookup
//      approach which can be done in the future [OPT:HYPER].
const Operations = defOps(.{
    .Stop = .{ .gas = 0, .desc = "Halt execution" },
    .Add = .{ .gas = 3, .desc = "(u)int256 addition modulo 2**256" },
    .Mul = .{ .gas = 5, .desc = "(u)int256 multiplication modulo 2**256" },
    // .Push1 = .{ .gas = 3, .desc = "Push 1-byte value onto stack" },
    // .Push32 = .{ .gas = 3, .desc = "Push 32-byte value onto stack" },
});

// /////////////////////////////////////////////////////////////////////////////
// //////////////// MAIN

pub fn main() !void {
    // print("Foonum: {any}\n\n", .{@intFromEnum(Foonum.Push26)});
    // print("All tags in Foonum: {any}\n", .{std.enums.values(Foonum)});

    // TODO: Specific allocator stuff later on. Doing this for now to get started.
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    for (args, 0..) |arg, i| {
        std.debug.print("{}: {s}\n", .{ i, arg });
    }

    print("Starting\n", .{});

    // TODO: This is not portable! Don't really care about Windows that much but
    //       it does also break WASI, need to use std.process.argsAlloc for
    //       Windows and WASI cross-compile support. Worry about this later
    //       though as we will probably do some kind of single allocation stuff
    //       which will encapsulate being given bytecode to execute as argv is
    //       being used for here. I'm doing this to force reading the bytecode
    //       as external data instead of some internal array of [_]OpCode{ ... };
    // const bytecode = std.mem.span(std.os.argv[1]);

    // const bytecode = std.os.argv[1];
    const bytecode = args[1];
    print("executing bytecode: {s}\n", .{bytecode});

    // TODO: Context struct for ROM and Stack, i.e. each VM has it's own context.
    var stack = try std.BoundedArray(u256, MAX_STACK_DEPTH).init(1);

    // Instruction pointer.
    var ip: u32 = 0;

    // TODO: EVM requires big-endian, move to that instead.
    // const foo = std.mem.readInt(u8, bytecode[ip..2], .little);
    // print("read byte: {s}\n", .{foo});

    // while (bytecode[ip] != 0) : (ip += 1) {
    //     // const c = bytecode[ip];
    //     print("ip: {d}, op: 0x{X})\n", .{ ip, ip });
    // }

    // // TODO: VM should be it's own structure (same as ROM and Stack all together).
    while (ip < bytecode.len) {
        const op = @intFromEnum(bytecode[ip]);

        print("ip: {d}, op: 0x{X})\n", .{ ip, op });

        // print("    operation: {s}\n", .{Operations[@intFromEnum(op)].desc});

        _ = switch (op) {
            .Stop => {
                print("Halting execution\n", .{});
                return;
            },
            .Add => {
                print("Add\n", .{});
            },
            .Mul => {
                print("Mul\n", .{});
            },
            .Sub => {
                print("Sub\n", .{});
            },
            .Div => {
                print("Div\n", .{});
            },
            .SDiv => {
                print("SDiv\n", .{});
            },
            .Push0 => {
                print("Push0\n", .{});
            },
            // PushN where N > 0 can be offset from Push1's opcode (0x60) to get
            //   the size of the operand in bytes and handle all 32 variants in
            //   one single prong.
            0x60...0x7F => {
                print("PushN\n", .{});
            },
            // PushN here
            .Create => {
                print("Create\n", .{});
            },
            .Call => {
                print("Call\n", .{});
            },
        };

        ip += 1;
    }

    print("Top of stack: {d}\n", .{stack.pop()});

    // print("Foonum: {any}\n\n", .{@intFromEnum(Foonum.Push26)});
    // print("All tags in Foonum: {any}\n", .{std.enums.values(Foonum)});
}

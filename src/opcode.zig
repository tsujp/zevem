const std = @import("std");
const print = std.debug.print;
const EnumField = std.builtin.Type.EnumField;

// /////////////////////////////////////////////////////////////////////////////
// //////////////// COMPTIME ENUM

// OPT:3: Add docstring comments as printable debug output e.g. for ADD it'd be "addition operating".
pub const OpCode = MakeOpCodes(.{
    // XXX: Deciding capitalisation is unintuitive (CallData vs Calldata and so on) so capitalise all.
    // zig fmt: off

    .{ "STOP", 0x00 }, // Halt execution.

    // Maths.
    .{"ADD"}, // Addition.
    .{"MUL"}, // Multiplication.
    .{"SUB"}, // Subtraction.
    .{"DIV"}, // Integer division.
    .{"SDIV"}, // Signed integer division (truncated).
    .{"MOD"}, // Modulo remainder.
    .{"SMOD"}, // Signed modulo remainder.
    .{"ADDMOD"}, // Modulo addition.
    .{"MULMOD"}, // Modulo multiplication.
    .{"EXP"}, // Exponential.

    .{"SIGNEXTEND"}, // Extend length of two's complement signed integer.

    //
    // UNUSED: 0x0C ... 0x0F
    //

    // Comparison.
    .{"LT", 0x10 }, // Less than.
    .{"GT"}, // Greater than.
    .{"SLT"}, // Signed less than.
    .{"SGT"}, // Signed greater than.
    .{"EQ"}, // Equality.
    .{"ISZERO"}, // Is zero.

    // Bitwise.
    .{"AND"}, // AND.
    .{"OR"}, // OR.
    .{"XOR"}, // XOR.
    .{"NOT"}, // NOT.

    .{"BYTE"}, // Retrieve single byte from word.
    .{"SHL"}, // Left-shift (TODO: What kind, bitwise?)
    .{"SHR"}, // Logical right-shift.
    .{"SAR"}, // Arithmetic signed right-shift.

    //
    // UNUSED: 0x1E ... 0x1F
    //

    .{"KECCAK256", 0x20}, // Compute KECCAK-256 hash.

    //
    // UNUSED: 0x21 ... 0x2F
    //

    // Environment / get information.
    .{"ADDRESS", 0x30}, // Get address of currently executing account.
    .{"BALANCE"}, // Get balance of account.
    .{"ORIGIN"}, // Get execution of origination address.
    .{"CALLER"}, // Get caller address.
    .{"CALLVALUE"}, // Get deposited value via instruction/transaction responsible for current execution.
    .{"CALLDATALOAD"}, // Get input data of current environment.
    .{"CALLDATASIZE"}, // Get size of input data in current environment.
    .{"CALLDATACOPY"}, // Copy input data in current environment to memory.
    .{"CODESIZE"}, // Get size of code running in current environment.
    .{"CODECOPY"}, // Copy code running in current environment to memory.
    .{"GASPRICE"}, // Get gas price in current environment.
    .{"EXTCODESIZE"}, // Get size of given account's code.
    .{"EXTCODECOPY"}, // Copy given account's code to memory.
    .{"RETURNDATASIZE"}, // Get size of output data from previous call in current environment.
    .{"RETURNDATACOPY"}, // Copy output data from previous call to memory.
    .{"EXTCODEHASH"}, // Get hash of given account's code.
    .{"BLOCKHASH"}, // Get hash of given complete block (within last 256).
    .{"COINBASE"}, // Get block's beneficiary address.
    .{"TIMESTAMP"}, // Get block's timestamp.
    .{"NUMBER"}, // Get block's ordinal number.
    .{"PREVRANDAO"}, // Get block's difficulty.
    .{"GASLIMIT"}, // Get block's gas limit.
    .{"CHAINID"}, // Get chain id.
    .{"SELFBALANCE"}, // Get balance of currently executing account.
    .{"BASEFEE"}, // Get base fee.
    .{"BLOBHASH"}, // Get versioned hashes.
    .{"BLOBBASEFEE"}, // Get block's blob base-fee.

    // UNUSED: 0x4B ... 0x4F

    .{"POP", 0x50},
    .{"MLOAD"},
    .{"MSTORE"},
    .{"MSTORE8"},
    .{"SLOAD"},
    .{"SSTORE"},
    .{"JUMP"},
    .{"JUMPI"},
    .{"PC"},
    .{"MSIZE"},
    .{"GAS"},
    .{"JUMPDEST"},
    .{"TLOAD"},
    .{"TSTORE"},
    .{"MCOPY"}, // Copy memory areas.

    .{ "PUSH0", 0x5F }, // Push 0 value on stack.
    // PUSH1 ... PUSH32
    .{ "PUSH", 0x60, 0x7F }, // Push N byte operand on stack.

    // DUP1 ... DUP16
    .{ "DUP", 0x80, 0x8F }, // Duplicate Nth stack item (TODO: To the top of the stack?)

    // SWAP1 ... SWAP16
    .{ "SWAP", 0x90, 0x9F }, // Swap N and N+1th stack items.

    .{"LOG0"}, // Append log record with 0 topics.
    // LOG1 ... LOG4
    .{ "LOG", 0xA1, 0xA4 }, // Append log record with N topics.

    //
    // UNUSED: 0xA5 ... 0xEF
    //

    .{ "CREATE", 0xF0 }, // Create new account with given code.
    .{"CALL"}, // Message-call into given account.
    .{"CALLCODE"}, // Message-call into account with alternative account's code.
    .{"RETURN"}, // Halt, return output data.
    .{"DELEGATECALL"}, //
    .{"CREATE2"}, // Create new account with given code at predictable address.

    //
    // UNUSED: 0xF6 ... 0xF9
    //

    .{ "STATICCALL", 0xFA }, // Static message call into account.

    //
    // UNUSED: 0xFB ... 0xFC
    //

    .{ "REVERT", 0xFD }, // Halt, revert state changes but still return data and remaining gas.
    .{"INVALID"}, // Well-known invalid instruction.
    .{"SELFDESTRUCT"}, // Halt execution and register account for later deletion OR send all Ether to address (cancun).
    // zig fmt: on
});

// Return enum field value.
fn enumField(comptime name: [:0]const u8, comptime value: u8) [1]EnumField {
    return [1]EnumField{.{ .name = name, .value = value }};
}

// Comptime construction of enum with fields over specified ranges.
fn MakeOpCodes(comptime defs: anytype) type {
    comptime var fields: []const EnumField = &[_]EnumField{};

    // JORDAN: zig 0.14.0-dev changes to Type union in builtin.zig
    if (@typeInfo(@TypeOf(defs)) != .@"struct") {
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
        .@"enum" = .{
            .tag_type = u8,
            .fields = fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_exhaustive = false,
        },
    });
}

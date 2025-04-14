//! Opcode definitions and compile-time creation.

const std = @import("std");
const print = std.debug.print;
const EnumField = std.builtin.Type.EnumField;
const comptimePrint = std.fmt.comptimePrint;

// XXX: Can't seem to access as struct members if using top-level fields in op.zig so consume from op.zig `pub const ...` instead.
pub const Enum = OpCodes.Enum;
pub const table = OpCodes.table;

// XXX: Arguably overengineered versus just hardcoding u8 and 256.
const OPCODE_SIZE = u8;
const MAX_OPCODE_COUNT: comptime_int = std.math.maxInt(OPCODE_SIZE) + 1;

const GasCost = struct {
    constant: FeeSchedule,
    // TODO: Dynamic.
};

// Instructions can have constant gas prices associated with them and/or dynamic gas prices associated with them.
// Instructions which alter memory size pay gas according to the magnitude of memory modified.
// 9.2 Fees Overview: three distinct circumstances, all prerequisite to instruction execution.
// 1. Fee intrinsic to operation (appendix G).
// 2. Fee for subordinate message call or contract creation (CREATE, CREATE2, CALL, CALLCODE).
// 3. Increase in usage of memory.
// Total fee for memory usage payable is proportional to smallest multiple of 32 bytes required such that all memory indices (read or write) are included in that range. Paid just-in-time. So, accessing area of memory at least 32 bytes greater than any previously indexed memory will result in increased fee.

// TODO: Map this to the scalar values of appendix G.
const FeeSchedule = enum {
    zero,
    jumpdest,
    base,
    verylow,
    low,
    mid,
    high,
    warmaccess,
    accesslistaddress,
    accessliststorage,
    coldaccountaccess,
    coldsload,
    sset,
    sreset,
    sclear,
    selfdestruct,
    create,
    codedeposit,
    initcodeword,
    callvalue,
    callstipend,
    newaccount,
    exp,
    expbyte,
    memory,
    txcreate,
    txdatazero,
    txdatanonzero,
    transaction,
    log,
    logdata,
    logtopic,
    keccak256,
    keccak256word,
    copy,
    blockhash,
    // TODO: Remove this field later.
    TODO_CUSTOM_FEE,
};

// Largest actual delta or alpha appears to be 7, so 3 bits.
const OpInfo = struct {
    // TODO: There are opcodes which have complex gas calculation functions so we should allow either a FeeSchedule or a pointer to a function that implements the gas cost computation as a value here.
    fee: GasCost,
    // Delta: stack items to be removed.
    delta: u3,
    // Alpha: stack items to be added.
    alpha: u3,
};

// /////////////////////////////////////////////////////////////////////////////
// //////////////// Comptime opcode definitions

// TODO: Double check the grouping of opcodes here.
// TODO: In progress adding gas cost and stack deltas (delete this when done)
//       --  0s:  complete
//       -- 10s:

const OpCodes = MakeOpCodes(.{
    // XXX: Deciding capitalisation is unintuitive (CallData vs Calldata and so on) so capitalise all.

    // //////////////////////////////////////////
    // /////// 0s: Stop and Arithmetic Operations
    .{ .STOP, .{0x00}, .zero, 0, 0 }, // Halt execution.

    // Maths.
    .{ .ADD, .{}, .verylow, 2, 1 }, // Addition.
    .{ .MUL, .{}, .low, 2, 1 }, // Multiplication.
    .{ .SUB, .{}, .verylow, 2, 1 }, // Subtraction.
    .{ .DIV, .{}, .low, 2, 1 }, // Integer division.
    .{ .SDIV, .{}, .low, 2, 1 }, // Signed integer division (truncated).
    .{ .MOD, .{}, .low, 2, 1 }, // Modulo remainder.
    .{ .SMOD, .{}, .low, 2, 1 }, // Signed modulo remainder.
    .{ .ADDMOD, .{}, .mid, 3, 1 }, // Modulo addition.
    .{ .MULMOD, .{}, .mid, 3, 1 }, // Modulo multiplication.
    .{ .EXP, .{}, .TODO_CUSTOM_FEE, 2, 1 }, // Exponential.
    //
    .{ .SIGNEXTEND, .{}, .low, 2, 1 }, // Extend length of two's complement signed integer.

    // UNUSED: 0x0C ... 0x0F

    // //////////////////////////////////////////
    // /////// 10s: Comparison & Bitwise Logic Operations

    // Comparison.
    .{ .LT, .{0x10}, .zero, 0, 0 }, // Less than.
    .{ .GT, .{}, .zero, 0, 0 }, // Greater than.
    .{ .SLT, .{}, .zero, 0, 0 }, // Signed less than.
    .{ .SGT, .{}, .zero, 0, 0 }, // Signed greater than.
    .{ .EQ, .{}, .zero, 0, 0 }, // Equality.
    .{ .ISZERO, .{}, .zero, 0, 0 }, // Is zero.
    //
    // Bitwise.
    .{ .AND, .{}, .zero, 0, 0 }, // AND.
    .{ .OR, .{}, .zero, 0, 0 }, // OR.
    .{ .XOR, .{}, .zero, 0, 0 }, // XOR.
    .{ .NOT, .{}, .zero, 0, 0 }, // NOT.
    //
    .{ .BYTE, .{}, .zero, 0, 0 }, // Retrieve single byte from word.
    .{ .SHL, .{}, .zero, 0, 0 }, // Left-shift (TODO: What kind, bitwise?)
    .{ .SHR, .{}, .zero, 0, 0 }, // Logical right-shift.
    .{ .SAR, .{}, .zero, 0, 0 }, // Arithmetic signed right-shift.

    // UNUSED: 0x1E ... 0x1F

    // //////////////////////////////////////////
    // /////// 20s: KECCAK256
    .{ .KECCAK256, .{0x20}, .zero, 0, 0 }, // Compute KECCAK-256 hash.

    // UNUSED: 0x21 ... 0x2F

    // //////////////////////////////////////////
    // /////// 30s: Environmental Information

    // Environment / get information.
    .{ .ADDRESS, .{0x30}, .zero, 0, 0 }, // Get address of currently executing account.
    .{ .BALANCE, .{}, .zero, 0, 0 }, // Get balance of account.
    .{ .ORIGIN, .{}, .zero, 0, 0 }, // Get execution of origination address.
    .{ .CALLER, .{}, .zero, 0, 0 }, // Get caller address.
    .{ .CALLVALUE, .{}, .zero, 0, 0 }, // Get deposited value via instruction/transaction responsible for current execution.
    .{ .CALLDATALOAD, .{}, .zero, 0, 0 }, // Get input data of current environment.
    .{ .CALLDATASIZE, .{}, .zero, 0, 0 }, // Get size of input data in current environment.
    .{ .CALLDATACOPY, .{}, .zero, 0, 0 }, // Copy input data in current environment to memory.
    .{ .CODESIZE, .{}, .zero, 0, 0 }, // Get size of code running in current environment.
    .{ .CODECOPY, .{}, .zero, 0, 0 }, // Copy code running in current environment to memory.
    .{ .GASPRICE, .{}, .zero, 0, 0 }, // Get gas price in current environment.
    .{ .EXTCODESIZE, .{}, .zero, 0, 0 }, // Get size of given account's code.
    .{ .EXTCODECOPY, .{}, .zero, 0, 0 }, // Copy given account's code to memory.
    .{ .RETURNDATASIZE, .{}, .zero, 0, 0 }, // Get size of output data from previous call in current environment.
    .{ .RETURNDATACOPY, .{}, .zero, 0, 0 }, // Copy output data from previous call to memory.
    .{ .EXTCODEHASH, .{}, .zero, 0, 0 }, // Get hash of given account's code.

    // //////////////////////////////////////////
    // /////// 40s: Block Information
    .{ .BLOCKHASH, .{}, .zero, 0, 0 }, // Get hash of given complete block (within last 256).
    .{ .COINBASE, .{}, .zero, 0, 0 }, // Get block's beneficiary address.
    .{ .TIMESTAMP, .{}, .zero, 0, 0 }, // Get block's timestamp.
    .{ .NUMBER, .{}, .zero, 0, 0 }, // Get block's ordinal number.
    .{ .PREVRANDAO, .{}, .zero, 0, 0 }, // Get block's difficulty.
    .{ .GASLIMIT, .{}, .zero, 0, 0 }, // Get block's gas limit.
    .{ .CHAINID, .{}, .zero, 0, 0 }, // Get chain id.
    .{ .SELFBALANCE, .{}, .zero, 0, 0 }, // Get balance of currently executing account.
    .{ .BASEFEE, .{}, .zero, 0, 0 }, // Get base fee.
    .{ .BLOBHASH, .{}, .zero, 0, 0 }, // Get versioned hashes.
    .{ .BLOBBASEFEE, .{}, .zero, 0, 0 }, // Get block's blob base-fee.

    // UNUSED: 0x4B ... 0x4F

    // //////////////////////////////////////////
    // /////// 50s: Stack, Memory, Storage and Flow Operations

    .{ .POP, .{0x50}, .zero, 0, 0 },
    .{ .MLOAD, .{}, .zero, 0, 0 },
    .{ .MSTORE, .{}, .zero, 0, 0 },
    .{ .MSTORE8, .{}, .zero, 0, 0 },
    .{ .SLOAD, .{}, .zero, 0, 0 },
    .{ .SSTORE, .{}, .zero, 0, 0 },
    .{ .JUMP, .{}, .zero, 0, 0 },
    .{ .JUMPI, .{}, .zero, 0, 0 },
    .{ .PC, .{}, .zero, 0, 0 },
    .{ .MSIZE, .{}, .zero, 0, 0 },
    .{ .GAS, .{}, .zero, 0, 0 },
    .{ .JUMPDEST, .{}, .zero, 0, 0 },
    .{ .TLOAD, .{}, .zero, 0, 0 },
    .{ .TSTORE, .{}, .zero, 0, 0 },
    .{ .MCOPY, .{}, .zero, 0, 0 }, // Copy memory areas.

    // //////////////////////////////////////////
    // /////// 5f, 60s & 70s: Push Operations
    .{ .PUSH0, .{0x5F}, .base, 0, 1 }, // Push 0 value on stack.
    // PUSH1 ... PUSH32
    .{ .PUSH, .{ 0x60, 0x7F }, .verylow, 0, 1 }, // Push N byte operand on stack.

    // //////////////////////////////////////////
    // /////// 80s: Duplication Operations

    // DUP1 ... DUP16
    .{ .DUP, .{ 0x80, 0x8F }, .zero, 0, 0 }, // Duplicate Nth stack item (TODO: To the top of the stack?)

    // //////////////////////////////////////////
    // /////// 90s: Exchange Operations

    // SWAP1 ... SWAP16
    .{ .SWAP, .{ 0x90, 0x9F }, .zero, 0, 0 }, // Swap N and N+1th stack items.

    // //////////////////////////////////////////
    // /////// a0s: Logging Operations

    // TOOD: LOG have different price values and stack deltas, enumerate manually.
    .{ .LOG0, .{}, .zero, 0, 0 }, // Append log record with 0 topics.
    // LOG1 ... LOG4
    .{ .LOG, .{ 0xA1, 0xA4 }, .zero, 0, 0 }, // Append log record with N topics.

    // UNUSED: 0xA5 ... 0xEF

    // //////////////////////////////////////////
    // /////// f0s: System operations
    .{ .CREATE, .{0xF0}, .zero, 0, 0 }, // Create new account with given code.
    .{ .CALL, .{}, .zero, 0, 0 }, // Message-call into given account.
    .{ .CALLCODE, .{}, .zero, 0, 0 }, // Message-call into account with alternative account's code.
    .{ .RETURN, .{}, .zero, 0, 0 }, // Halt, return output data.
    .{ .DELEGATECALL, .{}, .zero, 0, 0 }, //
    .{ .CREATE2, .{}, .zero, 0, 0 }, // Create new account with given code at predictable address.

    // UNUSED: 0xF6 ... 0xF9
    .{ .STATICCALL, .{0xFA}, .zero, 0, 0 }, // Static message call into account.

    // UNUSED: 0xFB ... 0xFC
    .{ .REVERT, .{0xFD}, .zero, 0, 0 }, // Halt, revert state changes but still return data and remaining gas.
    .{ .INVALID, .{}, .zero, 0, 0 }, // Well-known invalid instruction.
    .{ .SELFDESTRUCT, .{}, .zero, 0, 0 }, // Halt execution and register account for later deletion OR send all Ether to address (cancun).
});

// /////////////////////////////////////////////////////////////////////////////
// //////////////// Internal to constructing opcode definitions

fn makeEnumField(comptime name: [:0]const u8, comptime value: OPCODE_SIZE) EnumField {
    return .{ .name = name, .value = value };
}

fn makeOpInfo(comptime args: anytype) OpInfo {
    return .{ .fee = .{ .constant = args[2] }, .delta = args[3], .alpha = args[4] };
}

fn MakeOpCodes(comptime args: anytype) struct { Enum: type, table: [MAX_OPCODE_COUNT]OpInfo } {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);

    if (!(args_type_info == .@"struct" and args_type_info.@"struct".is_tuple == true)) {
        @compileError("expected tuple of definitions, got " ++ @typeName(ArgsType));
    }

    // TODO: Check if undefined for missing values is in-fact okay (or if we need a better type to represent those).
    comptime var enum_fields: []const EnumField = &.{};
    comptime var op_table: [MAX_OPCODE_COUNT]OpInfo = undefined;

    inline for (args) |df| {
        const name = df[0];
        if (@typeInfo(@TypeOf(name)) != .enum_literal) {
            @compileError("expected op name to be enum_literal, got " ++ @typeName(@TypeOf(name)));
        }
        const name_str = @tagName(name);

        // TODO: Check its actually a tuple (really just pedantic).
        const ord_def = df[1];

        enum_fields = enum_fields ++ outer: {
            break :outer [_]EnumField{switch (ord_def.len) {
                // Empty, infer ordinal +1 of previous.
                0 => blk: {
                    const v = enum_fields[enum_fields.len - 1].value + 1;

                    op_table[v] = makeOpInfo(df);
                    break :blk makeEnumField(name_str, v);
                },
                // Explicit ordinal, set as given.
                1 => blk: {
                    const v = ord_def[0];

                    op_table[v] = makeOpInfo(df);
                    break :blk makeEnumField(name_str, v);
                },
                // Explicit ordinal inclusive range, iterate and set.
                2 => {
                    const from = ord_def[0];
                    const to = ord_def[1] + 1;

                    comptime var iter: [to - from]EnumField = undefined;

                    for (from..to) |ord| {
                        op_table[ord] = makeOpInfo(df);
                        iter[ord - from] = makeEnumField(
                            std.fmt.comptimePrint("{s}{d}", .{ name_str, ord - from + 1 }),
                            ord,
                        );
                    }

                    break :outer &iter;
                },
                else => {
                    @compileError("TODO: too many values");
                },
            }};
        };
    }

    const OpEnum = @Type(.{ .@"enum" = .{
        .tag_type = OPCODE_SIZE,
        .fields = enum_fields,
        .decls = &.{},
        .is_exhaustive = true,
    } });

    return .{
        .Enum = OpEnum,
        .table = op_table,
    };
}

// pub const opTable = std.enums.directEnumArrayDefault(OpCode, OpInfo, .{ .fee = .zero, .delta = 0, .alpha = 0 }, 256, .{
//     .STOP = .{ .fee = .zero, .delta =  0, .alpha =  0},
//     .ADD = .{ .fee = .zero, .delta = 0, .alpha = 0},
// });
// pub const opTable = std.enums.directEnumArrayDefault(OpCode, OpInfo, null, 256, .{
//     .STOP = .{ .fee = .zero, .delta =  0, .alpha =  0},
//     .ADD = .{ .fee = .zero, .delta = 0, .alpha = 0},
// });

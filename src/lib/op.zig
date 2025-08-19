//! Opcode definitions and compile-time creation.

const std = @import("std");
const print = std.debug.print;
const EnumField = std.builtin.Type.EnumField;
const EnumMap = std.enums.EnumMap;
const comptimePrint = std.fmt.comptimePrint;

// XXX: Can't seem to access as struct members if using top-level fields in op.zig so consume from op.zig `pub const ...` instead.
pub const Enum = OpCodes.Enum;
pub const table = OpCodes.table;

pub const Fee = FeeSchedule;
pub const fee_table = fee_map;

// XXX: Arguably overengineered versus just hardcoding u8 and 256.
const OPCODE_SIZE = u8;
const MAX_OPCODE_COUNT: comptime_int = std.math.maxInt(OPCODE_SIZE) + 1;

const GasCostTag = enum {
    constant,
    dynamic,
};

// TODO: Yet to see any ops which have both constant and dynamic, if/when then this needs changing.
pub const GasCost = union(GasCostTag) {
    constant: FeeSchedule,
    dynamic: *const fn (self: *EVM) u64,
};

// Instructions can have constant gas prices associated with them and/or dynamic gas prices associated with them.
// Instructions which alter memory size pay gas according to the magnitude of memory modified.
// 9.2 Fees Overview: three distinct circumstances, all prerequisite to instruction execution.
// 1. Fee intrinsic to operation (appendix G).
// 2. Fee for subordinate message call or contract creation (CREATE, CREATE2, CALL, CALLCODE).
// 3. Increase in usage of memory.
// Total fee for memory usage payable is proportional to smallest multiple of 32 bytes required such that all memory indices (read or write) are included in that range. Paid just-in-time. So, accessing area of memory at least 32 bytes greater than any previously indexed memory will result in increased fee.

// Scalar values of appendix G.
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

// TODO: Can this be optimised?
// XXX: u16 would be maximum (via log2(32_000), since 32_000 is largest scalar in this set) but
//      since we need to count gas and BlockHeader, and EVM (anonymous struct) both use gas as
//      u64 we'll just use u64 here to prevent a lot of @intCast etc. Likely the latter is the
//      way to go in the end state if this EnumMap is still used, TL;DR optimise.
const fee_map = EnumMap(FeeSchedule, u16).init(.{
    .zero = 0,
    .jumpdest = 1,
    .base = 2,
    .verylow = 3,
    .low = 5,
    .mid = 8,
    .high = 10,
    .warmaccess = 1_000,
    .accesslistaddress = 2_400,
    .accessliststorage = 1_900,
    .coldaccountaccess = 2_600,
    .coldsload = 2_100,
    .sset = 20_000,
    .sreset = 2_900,
    .sclear = 4_800,
    .selfdestruct = 5_000,
    .create = 32_000,
    .codedeposit = 200,
    .initcodeword = 2,
    .callvalue = 9_000,
    .callstipend = 2_300,
    .newaccount = 25_000,
    .exp = 10,
    .expbyte = 50,
    .memory = 3,
    .txcreate = 32_000,
    .txdatazero = 4,
    .txdatanonzero = 16,
    .transaction = 21_000,
    .log = 375,
    .logdata = 8,
    .logtopic = 375,
    .keccak256 = 30,
    .keccak256word = 6,
    .copy = 3,
    .blockhash = 20,
    // TODO: Remove this field later.
    // .TODO_CUSTOM_FEE = 42069,
});

// TODO: Largest actual delta or alpha appears to be 7, so 3 bits, but using 5 to keep things more literal for now (i.e. SWAP and DUP large delta/alpha in yellowpaper).
const OpInfo = struct {
    // TODO: There are opcodes which have complex gas calculation functions so we should allow either a FeeSchedule or a pointer to a function that implements the gas cost computation as a value here.
    fee: GasCost,
    // Delta: stack items to be removed.
    delta: u5,
    // Alpha: stack items to be added.
    alpha: u5,
};

// /////////////////////////////////////////////////////////////////////////////
// //////////////// Comptime opcode definitions

// TODO: Why do DUP and SWAP have an asterisk next to them on page 29 yellowpaper for their gas cost? There is no qualifying asterisk that I can find... or is it the convention of * for intermediate value (in which case this makes no sense). I guess we'll find out when tests assert gas spent and we either pass or fail.
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
    .{ .EXP, .{}, gasEXP, 2, 1 }, // Exponential.
    //
    .{ .SIGNEXTEND, .{}, .low, 2, 1 }, // Extend length of two's complement signed integer.

    // UNUSED: 0x0C ... 0x0F

    // //////////////////////////////////////////
    // /////// 10s: Comparison & Bitwise Logic Operations

    // Comparison.
    .{ .LT, .{0x10}, .verylow, 2, 1 }, // Less than.
    .{ .GT, .{}, .verylow, 2, 1 }, // Greater than.
    .{ .SLT, .{}, .verylow, 2, 1 }, // Signed less than.
    .{ .SGT, .{}, .verylow, 2, 1 }, // Signed greater than.
    .{ .EQ, .{}, .verylow, 2, 1 }, // Equality.
    .{ .ISZERO, .{}, .verylow, 1, 1 }, // Is zero.
    //
    // Bitwise.
    .{ .AND, .{}, .verylow, 2, 1 }, // AND.
    .{ .OR, .{}, .verylow, 2, 1 }, // OR.
    .{ .XOR, .{}, .verylow, 2, 1 }, // XOR.
    .{ .NOT, .{}, .verylow, 1, 1 }, // NOT.
    //
    .{ .BYTE, .{}, .verylow, 2, 1 }, // Retrieve single byte from word.
    .{ .SHL, .{}, .verylow, 2, 1 }, // Left-shift (TODO: What kind, bitwise?)
    .{ .SHR, .{}, .verylow, 2, 1 }, // Logical right-shift.
    .{ .SAR, .{}, .verylow, 2, 1 }, // Arithmetic signed right-shift.

    // UNUSED: 0x1E ... 0x1F

    // //////////////////////////////////////////
    // /////// 20s: KECCAK256
    .{ .KECCAK256, .{0x20}, .TODO_CUSTOM_FEE, 2, 1 }, // Compute KECCAK-256 hash.

    // UNUSED: 0x21 ... 0x2F

    // //////////////////////////////////////////
    // /////// 30s: Environmental Information

    // Environment / get information.
    .{ .ADDRESS, .{0x30}, .base, 0, 1 }, // Get address of currently executing account.
    .{ .BALANCE, .{}, .TODO_CUSTOM_FEE, 1, 1 }, // Get balance of account.
    .{ .ORIGIN, .{}, .base, 0, 1 }, // Get execution of origination address.
    .{ .CALLER, .{}, .base, 0, 1 }, // Get caller address.
    .{ .CALLVALUE, .{}, .base, 0, 1 }, // Get deposited value via instruction/transaction responsible for current execution.
    .{ .CALLDATALOAD, .{}, .verylow, 1, 1 }, // Get input data of current environment.
    .{ .CALLDATASIZE, .{}, .base, 0, 1 }, // Get size of input data in current environment.
    .{ .CALLDATACOPY, .{}, .TODO_CUSTOM_FEE, 3, 0 }, // Copy input data in current environment to memory.
    .{ .CODESIZE, .{}, .base, 0, 1 }, // Get size of code running in current environment.
    .{ .CODECOPY, .{}, .TODO_CUSTOM_FEE, 3, 0 }, // Copy code running in current environment to memory.
    .{ .GASPRICE, .{}, .base, 0, 1 }, // Get gas price in current environment.
    .{ .EXTCODESIZE, .{}, .TODO_CUSTOM_FEE, 1, 1 }, // Get size of given account's code.
    .{ .EXTCODECOPY, .{}, .TODO_CUSTOM_FEE, 4, 0 }, // Copy given account's code to memory.
    .{ .RETURNDATASIZE, .{}, .base, 0, 1 }, // Get size of output data from previous call in current environment.
    .{ .RETURNDATACOPY, .{}, .TODO_CUSTOM_FEE, 3, 0 }, // Copy output data from previous call to memory.
    .{ .EXTCODEHASH, .{}, .TODO_CUSTOM_FEE, 1, 1 }, // Get hash of given account's code.

    // //////////////////////////////////////////
    // /////// 40s: Block Information
    .{ .BLOCKHASH, .{}, .blockhash, 1, 1 }, // Get hash of given complete block (within last 256).
    .{ .COINBASE, .{}, .base, 0, 1 }, // Get block's beneficiary address.
    .{ .TIMESTAMP, .{}, .base, 0, 1 }, // Get block's timestamp.
    .{ .NUMBER, .{}, .base, 0, 1 }, // Get block's ordinal number.
    .{ .PREVRANDAO, .{}, .base, 0, 1 }, // Get block's difficulty.
    .{ .GASLIMIT, .{}, .base, 0, 1 }, // Get block's gas limit.
    .{ .CHAINID, .{}, .base, 0, 1 }, // Get chain id.
    .{ .SELFBALANCE, .{}, .low, 0, 1 }, // Get balance of currently executing account.
    .{ .BASEFEE, .{}, .base, 0, 1 }, // Get base fee.
    .{ .BLOBHASH, .{}, .TODO_CUSTOM_FEE, 1, 1 }, // Get versioned hashes.
    .{ .BLOBBASEFEE, .{}, .TODO_CUSTOM_FEE, 0, 1 }, // Get block's blob base-fee.

    // UNUSED: 0x4B ... 0x4F

    // //////////////////////////////////////////
    // /////// 50s: Stack, Memory, Storage and Flow Operations

    .{ .POP, .{0x50}, .base, 1, 0 },
    .{ .MLOAD, .{}, .TODO_CUSTOM_FEE, 1, 1 },
    .{ .MSTORE, .{}, .TODO_CUSTOM_FEE, 2, 0 },
    .{ .MSTORE8, .{}, .TODO_CUSTOM_FEE, 2, 0 },
    .{ .SLOAD, .{}, .TODO_CUSTOM_FEE, 1, 1 },
    .{ .SSTORE, .{}, .TODO_CUSTOM_FEE, 2, 0 },
    .{ .JUMP, .{}, .mid, 1, 0 },
    .{ .JUMPI, .{}, .high, 2, 0 },
    .{ .PC, .{}, .base, 0, 1 },
    .{ .MSIZE, .{}, .base, 0, 1 },
    .{ .GAS, .{}, .base, 0, 1 },
    .{ .JUMPDEST, .{}, .jumpdest, 0, 0 },
    .{ .TLOAD, .{}, .TODO_CUSTOM_FEE, 1, 1 },
    .{ .TSTORE, .{}, .TODO_CUSTOM_FEE, 2, 0 },
    .{ .MCOPY, .{}, .TODO_CUSTOM_FEE, 3, 0 }, // Copy memory areas.

    // //////////////////////////////////////////
    // /////// 5f, 60s & 70s: Push Operations
    .{ .PUSH0, .{0x5F}, .base, 0, 1 }, // Push 0 value on stack.
    // PUSH1 ... PUSH32
    .{ .PUSH, .{ 0x60, 0x7F }, .verylow, 0, 1 }, // Push N byte operand on stack.

    // //////////////////////////////////////////
    // /////// 80s: Duplication Operations

    // DUP1 ... DUP16
    .{ .DUP, .{ 0x80, 0x8F }, .verylow, incrFrom(1), incrFrom(2) }, // Duplicate Nth stack item (TODO: To the top of the stack?)

    // //////////////////////////////////////////
    // /////// 90s: Exchange Operations

    // SWAP1 ... SWAP16
    .{ .SWAP, .{ 0x90, 0x9F }, .verylow, incrFrom(2), incrFrom(2) }, // Swap N and N+1th stack items.

    // //////////////////////////////////////////
    // /////// a0s: Logging Operations

    // TOOD: LOG have different price values and stack deltas, enumerate manually.
    .{ .LOG0, .{}, .TODO_CUSTOM_FEE, 2, 0 }, // Append log record with 0 topics.
    // LOG1 ... LOG4
    .{ .LOG, .{ 0xA1, 0xA4 }, .TODO_CUSTOM_FEE, incrFrom(3), 0 }, // Append log record with N topics.

    // UNUSED: 0xA5 ... 0xEF

    // //////////////////////////////////////////
    // /////// f0s: System operations
    .{ .CREATE, .{0xF0}, .TODO_CUSTOM_FEE, 3, 1 }, // Create new account with given code.
    .{ .CALL, .{}, .TODO_CUSTOM_FEE, 7, 1 }, // Message-call into given account.
    .{ .CALLCODE, .{}, .TODO_CUSTOM_FEE, 7, 1 }, // Message-call into account with alternative account's code.
    .{ .RETURN, .{}, .zero, 2, 0 }, // Halt, return output data.
    .{ .DELEGATECALL, .{}, .TODO_CUSTOM_FEE, 6, 1 }, //
    .{ .CREATE2, .{}, .TODO_CUSTOM_FEE, 4, 1 }, // Create new account with given code at predictable address.
    // UNUSED: 0xF6 ... 0xF9
    .{ .STATICCALL, .{0xFA}, .TODO_CUSTOM_FEE, 6, 1 }, // Static message call into account.
    // UNUSED: 0xFB ... 0xFC
    .{ .REVERT, .{0xFD}, .zero, 2, 0 }, // Halt, revert state changes but still return data and remaining gas.
    .{ .INVALID, .{}, .zero, 0, 0 }, // Well-known invalid instruction.
    .{ .SELFDESTRUCT, .{}, .selfdestruct, 1, 0 }, // Halt execution and register account for later deletion OR send all Ether to address (cancun).
});

// /////////////////////////////////////////////////////////////////////////////
// //////////////// Internal to constructing opcode definitions

fn makeEnumField(comptime name: [:0]const u8, comptime value: OPCODE_SIZE) EnumField {
    return .{ .name = name, .value = value };
}

fn makeOpInfo(comptime args: anytype, comptime override: ?struct { ?comptime_int, ?comptime_int }) OpInfo {
    // Due to the way I pass values to override we effectively need two checks here (which is being done). This can be cleaned up later when the comptime interface likely gets a rewrite after zevem works.
    const d_final, const a_final = blk: {
        const o = override orelse break :blk .{ args[3], args[4] };

        break :blk .{
            o[0] orelse args[3],
            o[1] orelse args[4],
        };
    };

    // @compileLog("ARG 2 INFO:", @TypeOf(args[2]));
    // @compileLog("ARG 2 INFO 2:", @typeInfo(@TypeOf(args[2])));

    return .{
        // .fee = .{ .constant = args[2] },
        // TODO: Possible to only return the inner .constant or .dynamic? Just curious.
        .fee = switch (@typeInfo(@TypeOf(args[2]))) {
            .enum_literal => GasCost{ .constant = args[2] },
            .@"fn" => GasCost{ .dynamic = args[2] },
            else => @compileError("expected fee tag or dynamic gas cost function, got " ++ @typeInfo(@TypeOf(args[2]))),
        },
        .delta = d_final,
        .alpha = a_final,
    };
}

// XXX: Could easily argue using a function here over tuple value like .{ .from = 2 } is silly but it gives us quick discrimination (just check if the type is a function).
fn incrFrom(comptime start_at: comptime_int) fn (comptime_int) comptime_int {
    return struct {
        pub fn call(comptime ordinal_offset: comptime_int) comptime_int {
            return start_at + ordinal_offset;
        }
    }.call;
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

                    op_table[v] = makeOpInfo(df, null);
                    break :blk makeEnumField(name_str, v);
                },
                // Explicit ordinal, set as given.
                1 => blk: {
                    const v = ord_def[0];

                    op_table[v] = makeOpInfo(df, null);
                    break :blk makeEnumField(name_str, v);
                },
                // Explicit ordinal inclusive range, iterate and set.
                2 => {
                    const from = ord_def[0];
                    const to = ord_def[1] + 1;

                    comptime var iter: [to - from]EnumField = undefined;

                    for (from..to) |ord| {
                        const offset = ord - from + 1;

                        op_table[ord] = makeOpInfo(df, .{
                            if (@typeInfo(@TypeOf(df[3])) == .@"fn") df[3](offset - 1) else null,
                            if (@typeInfo(@TypeOf(df[4])) == .@"fn") df[4](offset - 1) else null,
                        });

                        // @compileLog("OPINFO:", name_str, op_table[ord]);

                        iter[ord - from] = makeEnumField(
                            std.fmt.comptimePrint("{s}{d}", .{ name_str, offset }),
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

const evm = @import("evm.zig");
const DummyEnv = @import("DummyEnv.zig");
const EVM = evm.New(DummyEnv);

fn gasEXP(self: *EVM) u64 {
    // TODO: What happens if there's nothing at the index though? Model this after `.pop` on BoundedArray? Or custom data structure later?
    const exponent = self.stack.get(self.stack.len - 2);

    const base_fee = fee_table.get(.exp).?;

    // TODO: Optimise this to be branchless
    const fee = switch (exponent) {
        0 => base_fee,
        else => {
            return base_fee + (fee_table.get(.expbyte).? * ((256 - @clz(exponent) + 7) / 8));
        },
    };

    return fee;
}

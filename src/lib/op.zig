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

const types = @import("types.zig");

// XXX: Put Exception in types.zig?
const Exception = @import("evm.zig").Exception;

// TODO: Since moving stackOffTop into utils this import feels messy?
const stackOffTop = @import("zevem").utils.stackOffTop;

// XXX: Arguably overengineered versus just hardcoding u8 and 256.
const OPCODE_SIZE = u8;
const MAX_OPCODE_COUNT: comptime_int = std.math.maxInt(OPCODE_SIZE) + 1;

pub const GasCost = struct {
    constant: FeeSchedule,
    dynamic: ?*const fn (self: *EVM, maximum_memory_size: u64) Exception!u64,
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
    // Memory sizing function (if any).
    memory: ?*const fn (self: *EVM) Exception!u64,
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
    .{ .STOP, .{0x00}, .zero, null, 0, 0 }, // Halt execution.

    // Maths.
    .{ .ADD, .{}, .verylow, null, 2, 1 }, // Addition.
    .{ .MUL, .{}, .low, null, 2, 1 }, // Multiplication.
    .{ .SUB, .{}, .verylow, null, 2, 1 }, // Subtraction.
    .{ .DIV, .{}, .low, null, 2, 1 }, // Integer division.
    .{ .SDIV, .{}, .low, null, 2, 1 }, // Signed integer division (truncated).
    .{ .MOD, .{}, .low, null, 2, 1 }, // Modulo remainder.
    .{ .SMOD, .{}, .low, null, 2, 1 }, // Signed modulo remainder.
    .{ .ADDMOD, .{}, .mid, null, 3, 1 }, // Modulo addition.
    .{ .MULMOD, .{}, .mid, null, 3, 1 }, // Modulo multiplication.
    .{ .EXP, .{}, .exp, gasEXP, 2, 1 }, // Exponential.
    //
    .{ .SIGNEXTEND, .{}, .low, null, 2, 1 }, // Extend length of two's complement signed integer.

    // UNUSED: 0x0C ... 0x0F

    // //////////////////////////////////////////
    // /////// 10s: Comparison & Bitwise Logic Operations

    // Comparison.
    .{ .LT, .{0x10}, .verylow, null, 2, 1 }, // Less than.
    .{ .GT, .{}, .verylow, null, 2, 1 }, // Greater than.
    .{ .SLT, .{}, .verylow, null, 2, 1 }, // Signed less than.
    .{ .SGT, .{}, .verylow, null, 2, 1 }, // Signed greater than.
    .{ .EQ, .{}, .verylow, null, 2, 1 }, // Equality.
    .{ .ISZERO, .{}, .verylow, null, 1, 1 }, // Is zero.
    //
    // Bitwise.
    .{ .AND, .{}, .verylow, null, 2, 1 }, // AND.
    .{ .OR, .{}, .verylow, null, 2, 1 }, // OR.
    .{ .XOR, .{}, .verylow, null, 2, 1 }, // XOR.
    .{ .NOT, .{}, .verylow, null, 1, 1 }, // NOT.
    //
    .{ .BYTE, .{}, .verylow, null, 2, 1 }, // Retrieve single byte from word.
    .{ .SHL, .{}, .verylow, null, 2, 1 }, // Left-shift (TODO: What kind, bitwise?)
    .{ .SHR, .{}, .verylow, null, 2, 1 }, // Logical right-shift.
    .{ .SAR, .{}, .verylow, null, 2, 1 }, // Arithmetic signed right-shift.

    // UNUSED: 0x1E ... 0x1F

    // //////////////////////////////////////////
    // /////// 20s: KECCAK256
    // KECCAK256 should be something like simpleMemorySize(.{0}, .{1})
    // TODO: 2025/11/02 so in general is the current gas specification here fine? At current
    //       hindsight for KECCAK I have to do something like put G_keccak256 as the constant
    //       and then a function for the G_keccak256word stuff (see the gas cost schedule 326)
    //       or I could set the constant to 0 and have the G_keccak256 added to the G_keccak256word
    //       as it's literally written in 326. Both approaches work, might be overthiking this. The
    //       former feels fine, since G_keccak256word is paid for each additional (rouned up) word
    //       of input to the hash function.
    .{ .KECCAK256, .{0x20}, .keccak256, gasKECCAK256, 2, 1, simpleMemorySize(.{0}, .{1}) }, // Compute KECCAK-256 hash.

    // UNUSED: 0x21 ... 0x2F

    // //////////////////////////////////////////
    // /////// 30s: Environmental Information

    // Environment / get information.
    .{ .ADDRESS, .{0x30}, .base, null, 0, 1 }, // Get address of currently executing account.
    .{ .BALANCE, .{}, .TODO_CUSTOM_FEE, null, 1, 1 }, // Get balance of account.
    .{ .ORIGIN, .{}, .base, null, 0, 1 }, // Get execution of origination address.
    .{ .CALLER, .{}, .base, null, 0, 1 }, // Get caller address.
    .{ .CALLVALUE, .{}, .base, null, 0, 1 }, // Get deposited value via instruction/transaction responsible for current execution.
    .{ .CALLDATALOAD, .{}, .verylow, null, 1, 1 }, // Get input data of current environment.
    .{ .CALLDATASIZE, .{}, .base, null, 0, 1 }, // Get size of input data in current environment.
    .{ .CALLDATACOPY, .{}, .TODO_CUSTOM_FEE, null, 3, 0 }, // Copy input data in current environment to memory.
    .{ .CODESIZE, .{}, .base, null, 0, 1 }, // Get size of code running in current environment.
    .{ .CODECOPY, .{}, .TODO_CUSTOM_FEE, null, 3, 0 }, // Copy code running in current environment to memory.
    .{ .GASPRICE, .{}, .base, null, 0, 1 }, // Get gas price in current environment.
    .{ .EXTCODESIZE, .{}, .TODO_CUSTOM_FEE, null, 1, 1 }, // Get size of given account's code.
    .{ .EXTCODECOPY, .{}, .TODO_CUSTOM_FEE, null, 4, 0 }, // Copy given account's code to memory.
    .{ .RETURNDATASIZE, .{}, .base, null, 0, 1 }, // Get size of output data from previous call in current environment.
    .{ .RETURNDATACOPY, .{}, .TODO_CUSTOM_FEE, null, 3, 0 }, // Copy output data from previous call to memory.
    .{ .EXTCODEHASH, .{}, .TODO_CUSTOM_FEE, null, 1, 1 }, // Get hash of given account's code.

    // //////////////////////////////////////////
    // /////// 40s: Block Information
    .{ .BLOCKHASH, .{}, .blockhash, null, 1, 1 }, // Get hash of given complete block (within last 256).
    .{ .COINBASE, .{}, .base, null, 0, 1 }, // Get block's beneficiary address.
    .{ .TIMESTAMP, .{}, .base, null, 0, 1 }, // Get block's timestamp.
    .{ .NUMBER, .{}, .base, null, 0, 1 }, // Get block's ordinal number.
    .{ .PREVRANDAO, .{}, .base, null, 0, 1 }, // Get block's difficulty.
    .{ .GASLIMIT, .{}, .base, null, 0, 1 }, // Get block's gas limit.
    .{ .CHAINID, .{}, .base, null, 0, 1 }, // Get chain id.
    .{ .SELFBALANCE, .{}, .low, null, 0, 1 }, // Get balance of currently executing account.
    .{ .BASEFEE, .{}, .base, null, 0, 1 }, // Get base fee.
    .{ .BLOBHASH, .{}, .TODO_CUSTOM_FEE, null, 1, 1 }, // Get versioned hashes.
    .{ .BLOBBASEFEE, .{}, .TODO_CUSTOM_FEE, null, 0, 1 }, // Get block's blob base-fee.

    // UNUSED: 0x4B ... 0x4F

    // //////////////////////////////////////////
    // /////// 50s: Stack, Memory, Storage and Flow Operations

    .{ .POP, .{0x50}, .base, null, 1, 0 },
    .{ .MLOAD, .{}, .verylow, gasSimpleMemory, 1, 1, simpleMemorySize(.{0}, 32) },
    // .{ .MSTORE, .{}, .verylow, gasMemory, 2, 0 },
    // .{ .MSTORE, .{}, .{ .verylow, gasMemory }, 2, 0 }, // use this form but commented for now
    // .{ .MSTORE, .{}, .verylow, gasMemory, 2, 0, simpleMemoryExpansion(.{0}, 32) },
    .{ .MSTORE, .{}, .verylow, gasSimpleMemory, 2, 0, simpleMemorySize(.{0}, 32) },
    // .{ .MSTORE, .{}, .verylow, gasMemory, 2, 0, simpleMemoryExpansion(0, .{ 2 }) },
    .{ .MSTORE8, .{}, .verylow, gasSimpleMemory, 2, 0, simpleMemorySize(.{0}, 1) },
    .{ .SLOAD, .{}, .TODO_CUSTOM_FEE, null, 1, 1 },
    .{ .SSTORE, .{}, .TODO_CUSTOM_FEE, null, 2, 0 },
    .{ .JUMP, .{}, .mid, null, 1, 0 },
    .{ .JUMPI, .{}, .high, null, 2, 0 },
    .{ .PC, .{}, .base, null, 0, 1 },
    .{ .MSIZE, .{}, .base, null, 0, 1 },
    .{ .GAS, .{}, .base, null, 0, 1 },
    .{ .JUMPDEST, .{}, .jumpdest, null, 0, 0 },
    .{ .TLOAD, .{}, .TODO_CUSTOM_FEE, null, 1, 1 },
    .{ .TSTORE, .{}, .TODO_CUSTOM_FEE, null, 2, 0 },
    .{ .MCOPY, .{}, .TODO_CUSTOM_FEE, null, 3, 0 }, // Copy memory areas.

    // //////////////////////////////////////////
    // /////// 5f, 60s & 70s: Push Operations
    .{ .PUSH0, .{0x5F}, .base, null, 0, 1 }, // Push 0 value on stack.
    // PUSH1 ... PUSH32
    .{ .PUSH, .{ 0x60, 0x7F }, .verylow, null, 0, 1 }, // Push N byte operand on stack.

    // //////////////////////////////////////////
    // /////// 80s: Duplication Operations

    // DUP1 ... DUP16
    .{ .DUP, .{ 0x80, 0x8F }, .verylow, null, incrFrom(1), incrFrom(2) }, // Duplicate Nth stack item.

    // //////////////////////////////////////////
    // /////// 90s: Exchange Operations

    // SWAP1 ... SWAP16
    .{ .SWAP, .{ 0x90, 0x9F }, .verylow, null, incrFrom(2), incrFrom(2) }, // Swap N and N+1th stack items.

    // //////////////////////////////////////////
    // /////// a0s: Logging Operations

    // TOOD: LOG have different price values and stack deltas, enumerate manually.
    .{ .LOG0, .{}, .log, null, 2, 0, simpleMemorySize(.{0}, .{1}) }, // Append log record with 0 topics.
    // LOG1 ... LOG4
    .{ .LOG, .{ 0xA1, 0xA4 }, .log, null, incrFrom(3), 0, simpleMemorySize(.{0}, .{1}) }, // Append log record with N topics.

    // UNUSED: 0xA5 ... 0xEF

    // //////////////////////////////////////////
    // /////// f0s: System operations
    .{ .CREATE, .{0xF0}, .create, null, 3, 1, simpleMemorySize(.{1}, .{2}) }, // Create new account with given code.
    .{ .CALL, .{}, .TODO_CUSTOM_FEE, null, 7, 1 }, // Message-call into given account.
    .{ .CALLCODE, .{}, .TODO_CUSTOM_FEE, null, 7, 1 }, // Message-call into account with alternative account's code.
    .{ .RETURN, .{}, .zero, null, 2, 0 }, // Halt, return output data.
    .{ .DELEGATECALL, .{}, .TODO_CUSTOM_FEE, null, 6, 1 }, //
    // TODO: Needs G_codedeposit, G_initcodeword, and it's own custom CREATE2 gas calculation per (326), like how KECCAK256 has it's own. Check G_codedeposit and G_initcodeword are part of that in 326 or if we need to do those separately.
    .{ .CREATE2, .{}, .create, null, 4, 1, simpleMemorySize(.{1}, .{2}) }, // Create new account with given code at predictable address.
    // UNUSED: 0xF6 ... 0xF9
    .{ .STATICCALL, .{0xFA}, .TODO_CUSTOM_FEE, null, 6, 1 }, // Static message call into account.
    // UNUSED: 0xFB ... 0xFC
    .{ .REVERT, .{0xFD}, .zero, null, 2, 0 }, // Halt, revert state changes but still return data and remaining gas.
    .{ .INVALID, .{}, .zero, null, 0, 0 }, // Well-known invalid instruction.
    .{ .SELFDESTRUCT, .{}, .selfdestruct, null, 1, 0 }, // Halt execution and register account for later deletion OR send all Ether to address (cancun).
});

// /////////////////////////////////////////////////////////////////////////////
// //////////////// Internal to constructing opcode definitions

fn makeEnumField(comptime name: [:0]const u8, comptime value: OPCODE_SIZE) EnumField {
    return .{ .name = name, .value = value };
}

fn makeOpInfo(comptime args: anytype, comptime override: ?struct { ?comptime_int, ?comptime_int }) OpInfo {
    // Due to the way I pass values to override we effectively need two checks here (which is being done). This can be cleaned up later when the comptime interface likely gets a rewrite after zevem works.
    const d_final, const a_final = blk: {
        const o = override orelse break :blk .{ args[4], args[5] };

        break :blk .{
            o[0] orelse args[4],
            o[1] orelse args[5],
        };
    };

    // @compileLog("ARG 2 INFO:", @TypeOf(args[2]));
    // @compileLog("ARG 2 INFO 2:", @typeInfo(@TypeOf(args[2])));

    return .{
        // .fee = .{ .constant = args[2] },
        // TODO: Possible to only return the inner .constant or .dynamic? Just curious.
        // .fee = switch (@typeInfo(@TypeOf(args[2]))) {
        //     .enum_literal => GasCost{ .constant = args[2] },
        //     .@"fn" => GasCost{ .dynamic = args[2] },
        //     else => @compileError("expected fee tag or dynamic gas cost function, got " ++ @typeInfo(@TypeOf(args[2]))),
        // },
        // TODO: Type check args[3] is a function pointer or null.
        .fee = .{
            .constant = args[2],
            .dynamic = args[3],
        },
        .memory = if (args.len == 7) args[6] else null,
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
                            if (@typeInfo(@TypeOf(df[4])) == .@"fn") df[4](offset - 1) else null,
                            if (@typeInfo(@TypeOf(df[5])) == .@"fn") df[5](offset - 1) else null,
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

// TODO: Force inline via `inline` or let compiler figure it out? Zig `inline` has additional semantics beyond just inlining.
// TODO: u10 somewhat arbitrary, max stack length is 1024 and 2^10 = 1024. Is being this specific on parameter value here fine?
// fn stackOffTop(self: *EVM, index: u10) types.Word {
//     // TODO: Do we need assert here, double check if Zig gives us bounds checking for free on _runtime_ slice values (BoundedArray.get accesses the backing slice by index). I don't think we do, only for comptime known.
//     return self.stack.get(self.stack.len - index - 1);
// }

fn gasEXP(self: *EVM, u_i__expanded: u64) Exception!u64 {
    _ = u_i__expanded;

    // TODO: What happens if there's nothing at the index though? Model this after `.pop` on BoundedArray? Or custom data structure later?
    const exponent = self.stack.get(self.stack.len - 2);

    // G_exp is assigned to EXP's constant pricing since it is common to both variants.
    return fee_table.get(.expbyte).? * ((256 - @clz(exponent) + 7) / 8);
}

/// KECCAK256 gas cost function for (326), specifically the additional word component.
fn gasKECCAK256(self: *EVM, u_i__expanded: u64) Exception!u64 {
    _ = u_i__expanded;
    // std.debug.print("gasKECCAK256 u_i expanded: {d}\n", .{u_i__expanded});

    // KECCAK256 s[1].
    const length: u64 = @intCast(stackOffTop(self, 1));

    if (length == 0) return 0;

    // Each word (rounded-up) of input data to KECCAK256.
    return fee_table.get(.keccak256word).? * (@divFloor(length - 1, 32) + 1);
}

// Gas payable due to change in size of addressed memory (but specifically for MSTORE-type resizes).
// TODO: Better doc-ish comment here.
// TODO: Put this on MSTORE et al as their dynamic cost function, but really it's for any change in memory size. Another table for this or another way to associate to relevant opcodes? This seems fine _for now_.
// TODO: Instead of another tuple element on MakeOpCodes, going to call the memory expansion function required by an opcodes dynamic gas calculation from within the latter. This means it's not easy to change at runtime but a bunch of stuff is going to probably need to be changed for easier enacting of that anyway so _for now_ this is fine and beats adding another element to comptime construct as recently done for dynamic gas.
// This is specifically memory expansions of the form: max(μ_i, ceil((μ_s[0] + 32) ÷ 32)) as
//   found on opcodes like MSTORE.
// TODO: Better name?
/// TODO: Doc comment for this function (how it's not the general M but specific to MSTORE and some specific friends).
// TODO: Is it items or size? For a rename of `u_i__expanded` to say `expanded_memory_items`.
// TODO: 2025/11/02 actually this is C_mem right so it's general???????????
fn gasSimpleMemory(self: *EVM, u_i__expanded: u64) Exception!u64 {
    // TODO 2025/09/09: since we check for overflow here, should we remove such checks from the
    //                  relevant opcode's implementation (e.g. the @addWithOverflow in MSTORE)?

    // 32 bytes in a Word (u256).
    const u_i__current = self.mem.items.len / 32;
    const u_i__change = u_i__expanded - u_i__current;

    // 0x1FFFFFFFE0 yoinked from Geth when trying to optimise ludicrous change deltas near u64 max.
    if (u_i__change > 0x1fffffffe0) {
        return Exception.OutOfGas;
    }

    const cost = (3 * u_i__change) + @divFloor(u_i__change * u_i__change, 512);

    return cost;
}

// TODO: Only pub export this in debug build.
// TODO: Better data structure and implementation in future. Unsure if Zig will automatically
//       de-duplicate the repeated strings currently (could test this later on).
// Ugly map of stack annotations per opcode for trace output.
pub const annotation = MakeOpAnnotations(.{
    .{ .{ .ADD, .MUL, .SUB, .LT, .GT, .SLT, .SGT, .EQ, .AND, .OR, .XOR }, .{ .{ "a", "b" }, .{"result"} } },
    .{ .{ .DIV, .SDIV }, .{ .{ "num", "denom" }, .{"result"} } },
    .{ .{ .MOD, .SMOD }, .{ .{ "a", "mod" }, .{"result"} } },
    .{ .{ .ADDMOD, .MULMOD }, .{ .{ "a", "b", "mod" }, .{"result"} } },
    .{ .{.EXP}, .{ .{ "base", "exp" }, .{"result"} } },
    .{ .{.SIGNEXTEND}, .{ .{ "byte_size", "a" }, .{"result"} } },
    .{ .{ .ISZERO, .NOT }, .{ .{"a"}, .{"result"} } },
    .{ .{.BYTE}, .{ .{ "msb_offset", "operand" }, .{"result"} } },
    .{ .{ .SHL, .SHR, .SAR }, .{ .{ "bits", "operand" }, .{"result"} } },
    .{ .{.KECCAK256}, .{ .{ "offset", "length" }, .{"digest"} } },
    .{ .{.CALLDATASIZE}, .{ .{"size"}, .{} } },
    .{ .{.ORIGIN}, .{ .{}, .{"addr"} } },
    .{ .{.POP}, .{ .{"discard"}, .{} } },
    .{ .{.MLOAD}, .{ .{"offset"}, .{"bytes"} } },
    .{ .{ .MSTORE, .MSTORE8 }, .{ .{ "offset", "value" }, .{} } },
    .{ .{.JUMP}, .{ .{"addr"}, .{} } },
    .{ .{.JUMPI}, .{ .{ "addr", "cond" }, .{} } },
    .{ .{.PC}, .{ .{}, .{"pc"} } },
    .{ .{.GAS}, .{ .{}, .{"gas"} } },
    .{ .{.PUSH0}, .{ .{}, .{"constant"} } },
    .{ .{ 32, .PUSH }, .{ .{}, .{"bytes"} } },
    .{ .{ 16, .DUP }, .{ .{.{ incrFrom(1), .DUP1, "to_copy" }}, .{"copied"} } },

    // TODO: CALLER, CODESIZE, CALLVALUE, GASPRICE, ADDRESS, CHAINID, SELFBALANCE.

    // TODO 2025/11/27: Need to redo how annotations are rendered and constructed. The actual printing to console is in EVM.nextOp but that of course depends on how they are defined. Essentially, the 0 <<-- and 0 -->> stuff works for almost all cases but we want to separately also be able to specify the index of the arguments to the opcode being called, not just the index they are affecting (as is the case now). This gets fucky with SWAP specifically.
    .{ .{ 16, .SWAP }, .{ .{}, .{ "summoned", .{ incrFrom(2), .SWAP1, "banished" } } } },
});

const StackAnnotation = struct {
    index: u10,
    text: []const u8,
};

pub const OpAnnotation = struct {
    delta: []const StackAnnotation,
    alpha: []const StackAnnotation,
};

// Given a single annotation definition tuple (delta/alpha) construct the annotation indices and
//   associated values for that delta/alpha.
fn makeAnnotation(op: OpCodes.Enum, annotation_def: anytype, data: [*]StackAnnotation) void {
    // Each element of the definition tuple.
    for (annotation_def, 0..) |adf, adf_i| {
        // TODO: Ordinal + previous to allow for mixing like opcode range definitions? I don't
        //       think we'll ever need that though its either implied indices or incrFrom i.e. they
        //       are mutually exclusive.

        switch (@typeInfo(@TypeOf(adf))) {
            .pointer => |ad_type_info| {
                if (!(ad_type_info.is_const == true and
                    ad_type_info.child == [adf.len:0]u8 and
                    ad_type_info.sentinel_ptr == null))
                {
                    @compileError("annotation definition: expected null-terminated slice of u8, got " ++ adf);
                }

                // It's a slice! Simples!
                data[adf_i] = .{ .index = adf_i, .text = adf };
            },
            .@"struct" => |ad_type_info| {
                if (ad_type_info.is_tuple == false) {
                    @compileError("annotation definition: expected tuple, got " ++ ad_type_info);
                }

                const length = ad_type_info.fields.len;
                const adti_fields = ad_type_info.fields;

                if (length <= 1) {
                    var buf: [12]u8 = undefined;
                    const length_str = try std.fmt.bufPrint(&buf, "{}", .{length});
                    @compileError("annotation definition: expected tuple with at least 2 elements, got " ++ length_str);
                }

                // Last argument must always be a string.
                if (isNullTerminatedSlice(adf[length - 1]) == false) {
                    @compileError("annotation definition: expected string in last element of auto-increment definition");
                }

                switch (length) {
                    // No offset, [0] must be an integer.
                    2 => {
                        if (adti_fields[0].type != comptime_int) {
                            @compileError("annotation definition: first element of 2-element auto-increment must be comptime_int");
                        }

                        data[adf_i] = .{
                            .index = adf[0],
                            .text = adf[1],
                        };
                    },
                    // Offset, [0] must be fn (comptime_int) comptime_int, [1] enum offset.
                    3 => {
                        if (adti_fields[0].type != fn (comptime_int) comptime_int) {
                            @compileError("annotation definition: first element of 3-element auto-increment must function of prototype: fn (comptime_int) comptime_int");
                        }

                        // TODO: Check enum at index 1 (i.e. 2nd element) is actually in OpCodes.Enum
                        const offset = @intFromEnum(op) - @intFromEnum(@field(OpCodes.Enum, @tagName(adf[1])));
                        const idx = adf[0](offset) - 1;

                        data[adf_i] = .{
                            .index = idx,
                            .text = adf[2],
                        };
                    },
                    else => {
                        @compileError("annotation definition: too many arguments to tuple, expect 2 or 3");
                    },
                }
            },
            else => {
                // TODO: cbf typing a full error string here right now. I know what it is and this will likely change so making it this robust right now is kinda exhausting honestly, or I am just tired and my brain is getting into "annoyed at everything" mode.
                @compileError("annotation definition: bad type");
            },
        }
    }
}

fn isNullTerminatedSlice(comptime args: anytype) bool {
    switch (@typeInfo(@TypeOf(args))) {
        .pointer => |type_info| {
            if (!(type_info.is_const == true and
                type_info.child == [args.len:0]u8 and
                type_info.sentinel_ptr == null))
            {
                return false;
            }

            return true;
        },
        else => {
            return false;
        },
    }
}

fn MakeOpAnnotations(comptime args: anytype) EnumMap(OpCodes.Enum, OpAnnotation) {
    @setEvalBranchQuota(10_000);

    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);

    if (!(args_type_info == .@"struct" and args_type_info.@"struct".is_tuple == true)) {
        @compileError("expected tuple of definitions, got " ++ @typeName(ArgsType));
    }

    comptime var op_map: EnumMap(OpCodes.Enum, OpAnnotation) = .{};

    // Each "top-level" tuple argument.
    inline for (args) |df| {
        const key_def = df[0];

        const kd_type_info = @typeInfo(@TypeOf(key_def));
        if (!(kd_type_info == .@"struct" and kd_type_info.@"struct".is_tuple == true)) {
            @compileError("expected op to annotate to be a tuple, got " ++ @typeName(@TypeOf(key_def)));
        }
        const kdti_struct = kd_type_info.@"struct";

        // If the first element of the op(s) to annotate is an integer that means we will iterate
        //   and construct op names in combination with the second (and final) element.
        const repeat_count = if (kdti_struct.fields[0].type == comptime_int) blk: {
            if (kdti_struct.fields.len == 2 and @typeInfo(@TypeOf(key_def[1])) == .enum_literal) {
                break :blk key_def[0];
            } else {
                @compileError("iterated op definition tuples must consist of exactly 2 items: an integer count of the number of times to iterate; and the base op name, got " ++ key_def);
            }
        } else 0;

        // TODO: Get this if-else set smaller/more-compact? Set from if-expression directly or
        //       some other pattern. This works so is fine for now.
        // Pre-enumerate op-names to reduce branching complexity and share some logic (like setting
        //   the actual annotation value) later.
        const op_names = if (repeat_count > 0) blk: {
            comptime var _n: [repeat_count]OpCodes.Enum = undefined;

            const name_str = @tagName(key_def[1]);

            inline for (0..repeat_count) |rci| {
                _n[rci] = @field(OpCodes.Enum, std.fmt.comptimePrint("{s}{d}", .{ name_str, rci + 1 }));
            }

            break :blk _n;
        } else blk: {
            comptime var _n: [kdti_struct.fields.len]OpCodes.Enum = undefined;

            inline for (key_def, 0..) |k, i| {
                _n[i] = k;
            }

            break :blk _n;
        };

        // Each op name we constructed.
        for (op_names) |on| {
            const annotation_def = df[1];

            comptime var delta_annotation: [annotation_def[0].len]StackAnnotation = undefined;
            comptime var alpha_annotation: [annotation_def[1].len]StackAnnotation = undefined;

            makeAnnotation(on, annotation_def[0], &delta_annotation);
            makeAnnotation(on, annotation_def[1], &alpha_annotation);

            // Required to force comptime data into correct location in binary, otherwise compiler
            //   errors.
            // See:  https://ziggit.dev/t/comptime-mutable-memory-changes/3702
            const da2 = delta_annotation;
            const aa2 = alpha_annotation;

            op_map.put(on, .{
                .delta = &da2,
                .alpha = &aa2,
            });
        }
    }

    return op_map;
}

// TODO: Better name?
/// Memory-expansion (330, pg.30) computes new μ_i (active number of words in machine memory)
///   given s, f, l. Where `s` is the current/before/existing μ_i ; `f` is some base number to
///   offset which ; `l` is a length added to f.
fn getMemorySizeChange(s: types.Word, f: types.Word, l: types.Word) Exception!u64 {
    if (l == 0) return @intCast(s);

    const u_i__before = s;
    const new_max_address = @addWithOverflow(f, l);
    const u_i__after = @divFloor(new_max_address[0] - 1, 32) + 1;

    // Use of M (when l is not zero) simplifies to the common form of custom μ_i found on opcodes
    //   like MSTORE. Thus we can use this function for all memory expansion cases.
    // TODO: List the various forms per the physical notes on FOO123 paper.

    // TODO: Perhaps call this function from within opcode bodies instead of copy-pasting memory
    //       expansion everywhere. In general just clean up the flow with this and simpleMemorySize
    //       gasSimpleMemory. I believe I correctly/cleanly separated the concerns here but the
    //       similar function names, and duplicated logic within opcode implementations is slightly
    //       confusing. So this general area is low-hanging fruit for cleanup.
    // TODO: Also re-check how these functions are called, it's currently tied to the gas stuff but
    //       we need the sizing for opcodes that must set new u_i so we should be able to access
    //       this value (without having to run the function or equivalent logic more than once)
    //       in opcode bodies that need it, like MSTORE etc (see FOO123) for complete list.

    // TODO 2025/09/09: the logging here should (ideally) be with the rest in nextOp but it's easier to put it here for now. A generic-ish "change in memory size" logging should be made later.
    // TODO 2025/11/02: The logging for this i.e. u_i__after is.. weird? e.g. =(32, 2) I cannot remember.
    // e.g. 0:0001(1)    51 MLOAD   mem_words=(32, 1)  mem_bytes=(32, false)  gas=(3, 0, 78995)
    //      0:0002(2)    51 MLOAD   mem_words=(32, 2)  mem_bytes=(34, false)  gas=(3, 0, 78994)
    // This would appear before `gas=` on the same line as the opcode name.
    // TODO: This should log the next multiple of 32 for mem_bytes, i.e.
    //                         // Next multiple of 32.
    // const u_i__after: usize = @intCast(32 * (@divFloor(new_max_address[0] - 1, 32) + 1));
    print("  mem_words=({d}, {d})  mem_bytes=({d}, unaligned={d}, overflow={})", .{ u_i__before, u_i__after, u_i__after * 32, new_max_address[0], new_max_address[1] == 1 });

    if (new_max_address[1] == 1) {
        return Exception.MemResizeUInt256Overflow;
    }

    // Treating as as u64, all the while that's true just truncate here since we'll hit out of gas later anyway.
    return @truncate(@max(s, u_i__after));
    // const res: u64 = @truncate(@max(s, u_i__after));
    // print("calculateMemoryCost s={d}, f={d}, l={d} -- {d}, {d}, {d} -- {d}\n", .{ s, f, l, u_i__before, u_i__after, new_max_address[0], res });
    // return res;
}

// TODO: Doc comment here about how this is for simpler memory expansion forms such as those for MSTORE, MLOAD, RETURN, REVERT, KECCAK256 etc as on paper note FOO123. Mention how parameter names f and l are from memory-expansion function M from yellow paper.
// XXX: Could use union instead if needed.
fn simpleMemorySize(f: struct { u10 }, l: anytype) fn (self: *EVM) Exception!u64 {
    // Implicit (and thus not accepted as a parameter) first argument s to M of μ_i.
    // const u_i__current = self.mem.items.len;

    // Indices are taken as tuples of single u10 integers since array literals like `[0]` are not
    //   a thing.

    // Argument f to M can always be taken as an index because f isn't used any other way.
    // Argument l to M should be either an integer, in which case it's used as an offset length
    //   from f, or an index to the stack item which defines that offset length.

    return struct {
        pub fn call(self: *EVM) Exception!u64 {
            const f_stack_index = stackOffTop(self, f[0]);

            const l_reified = blk: switch (@typeInfo(@TypeOf(l))) {
                // Hardcoded integer length, e.g. 32 as in MSTORE's: μ_s[0] + 32
                .comptime_int => {
                    break :blk l;
                },
                // Length taken from stack item at index, e.g. 1 as in RETURN's: μ_s[0] + μ_s[1]
                .@"struct" => |l_type_info| {
                    // Don't need to check l[0] >= std.math.maxInt(u10), Zig does it for us.
                    if (!(l_type_info.is_tuple == true or l_type_info.fields.len == 1)) {
                        @compileError("memory size: expected tuple of single u10, got " ++ l_type_info);
                    }

                    break :blk stackOffTop(self, l[0]);
                },
                else => {
                    @compileError("memory size: TODO BETTER ERROR, but bad data");
                },
            };

            return getMemorySizeChange(self.mem.items.len / 32, f_stack_index, l_reified);

            // const res = f_stack_index + l_reified;
            // std.debug.print("DONE: {any}\n", .{l_reified});
            // return res;
        }
    }.call;
}

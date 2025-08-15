//! Transaction information relevant to EVM execution.

// TODO: Rename this? At current progress (2025/08/12) meant to encompass a transaction beit
//       message call or contract creation.

const types = @import("../types.zig");

const Transaction = @This();

// Common fields

// TODO: Nonce, value, r, s, etc.

/// Transaction's gas limit: T_g
gas: u64,

// TODO: Is this actually common to all? I don't think so (double check paper notes etc).
/// Arbitrary sized byte array of input data to message call: T_d
data: []const u8,

// pub const default: Transaction = .{
//     .gas = 21_000, // Lowest which covers intrinsic (g_0) minimum (G_transaction).
//     .data = "",
// };
// pub fn init(comptime base: Transaction) Transaction {
//     const ArgsType = @TypeOf(base);
//     const args_type_info = @typeInfo(ArgsType);

//     // @compileLog("TYPE:", ArgsType);
//     // @compileLog("INFO:", args_type_info);

//     return .{
//         .gas = 21_000,
//         .data = "",
//     };
// }

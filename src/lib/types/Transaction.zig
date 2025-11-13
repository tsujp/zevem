//! Transaction information relevant to EVM execution.

// TODO: Rename this? At current progress (2025/08/12) meant to encompass a transaction beit
//       message call or contract creation.

const types = @import("../types.zig");

const Transaction = @This();

// Common fields

// TODO: Nonce, value, r, s, etc.

// T_s is a 160-bit address.
/// Transaction's sender: T_s
sender: types.Address,

/// Transaction's gas limit: T_g
gas: u64,

// If a transaction message call it's T_d, otherwise I_d which is part of the EVM's execution
//   environment.
/// Arbitrary sized byte array of input data to transaction: T_d OR I_d
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

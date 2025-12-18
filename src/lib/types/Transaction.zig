//! Transaction information relevant to EVM execution.

// TODO: Rename this? At current progress (2025/08/12) meant to encompass a transaction beit
//       message call or contract creation.
// TODO 2025/11/28 union of struct types for various transactions? How we want the library API to look will decide this I think. For now not doing so (it _appears_ like there's no need to yet).

const types = @import("../types.zig");

const Transaction = @This();

// Common fields

// TODO: Nonce, r, , etc.

// TODO: Need to put some clarity here on T_s and I_s interaction, for now this is fine. User must supply this even for nested calls so we can "stupidly" just treat this as I_s. Clarity once library actually used.
// T_s is a 160-bit address.
/// Transaction's sender: T_s
sender: types.Address,

// TODO: Until library abstraction boundry clearer just assuming T_v is always I_v, user must construct nested calls (setting new appropriate I_v) themselves.
// TODO: `Word` type fine? Just using it for now for simplicity. Probably can be the same as the gas ceiling since ETH supply is nowhere near what a u256 can fit.
/// Transaction's value in wei: T_v
value: types.Word,

/// Transaction's gas limit: T_g
gas: u64,

// TODO: Better docs on this maybe, but importantly user sets this field by doing 64, 66, 67, 68 of the YP (probably), we don't do that so this is the pre-calculated value that becomes the EVM's I_p.
// TODO: Actually use this field (currently just exists and not being used at all).
/// Transaction's condensed gas price: T_p, T_m, T_f
gas_price: u64,

// For CONTRACT CREATION T_i supplies this field.
// For MESSAGE CALL the code stored at the address of the contract supplies this field.
/// Arbitrary sized byte array of EVM bytecode to execute: I_b
code: []const u8,

// Only supply-able for MESSAGE CALL as additional input data for contract.
/// Arbitrary sized byte array of input data to transaction: I_d
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

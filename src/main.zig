const std = @import("std");
const print = std.debug.print;
const EnumField = std.builtin.Type.EnumField;

const Foonum = MakeOpCodes(.{
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

pub fn enumField(comptime name: []const u8, comptime value: u8) [1]EnumField {
    return [1]EnumField{.{ .name = name, .value = value }};
}

pub fn MakeOpCodes(comptime defs: anytype) type {
    comptime var fields: []const EnumField = &[_]EnumField{};

    if (@typeInfo(@TypeOf(defs)) != .Struct) {
        @compileError("expected tuple, found " ++ @typeName(@TypeOf(defs)));
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
pub fn main() !void {
    print("Foonum: {any}\n\n", .{@intFromEnum(Foonum.Push26)});
    // print("All tags in Foonum: {any}\n", .{std.enums.values(Foonum)});
}

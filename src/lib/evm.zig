const std = @import("std");
const print = std.debug.print;
const OpCode = @import("opcode.zig").OpCode;
const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();

const tracy = @import("tracy");

const MAX_STACK_DEPTH = 1024;

const WORD = u256;
const DOUBLE_WORD = u512;

const SIGNED_WORD = i256;

const WORD_SIGN_MASK = (1 << @typeInfo(WORD).int.bits - 1);

const WORD_MAX: WORD = std.math.maxInt(WORD);

const BYTES_IN_WORD = @divExact(@typeInfo(WORD).int.bits, 8);
const BITS_IN_WORD: u16 = @typeInfo(WORD).int.bits;

// TODO: EVM single allocation at start (configurable size or avoid using that strategy). Pass in desired context along with bytecode for easier simulation (e.g. devs, EIPs etc). For now: make a VM with pre-canned bytecode.
// TODO: Scoped logging.

const TraceEndline = enum {
    endln,
    cntln,
};

// XXX: Could have an instruction struct/enum/tagged-union which @calls and inlines some so OP_PUSH3 finds the associated (internal) instruction which has the logic to execute OP_PUSH3 but also things like gas pricing, and any logging. Investigate later, feels too spaghetti for right now.
// TODO: Better interface/implementation or just _stuff_ around tracing; idk. Do later even though it's extremely tempting to hack on cool comptime things now.
fn traceOp(op: OpCode, pc: usize, endline: TraceEndline) void {
    print("{x:0>6}\u{001b}[2m:{d:<3}\u{001b}[0m  \u{001b}[2m{x:0>2}:\u{001b}[0m{s:<6}{s}", .{ pc, pc, @intFromEnum(op), @tagName(op), if (endline == .endln) "\n" else "\t" });
}

// Meant to print _additional_ information for PUSH1 ... PUSH32.
fn traceOpPush(pc: usize, operand: WORD) void {
    print("new_pc={d}, pushed=0x{x}\n", .{ pc, operand });
}

// Meant to print _additional_ information for opcodes which take 2 items off the stack then put 1 back on.
fn traceStackTake() void {}

pub const EvmError = error{
    Revert,
};

pub fn New(comptime Environment: type) type {
    return struct {
        const Self = @This();
        // TODO: ROM context.
        // TODO: Nested EVMs.
        // TODO: Gas.
        env: *Environment,

        // TODO: Custom data structure for our stack (optimisation).
        stack: std.BoundedArray(WORD, MAX_STACK_DEPTH),

        /// Program counter / Instruction pointer.
        // TODO: By spec is a u256, cannot use a u256 to address std.BoundedArray as-is. Fix later.
        pc: usize,

        // TODO: Zig 0.14.0 deprecates managed container types. Unmanaged container types must pass the same allocator at the callsite for methods which require it and do so every time. Perhaps create a wrapper (or appropriate custom type) later on to ease this (potential) burden. Zig std ArrayHashMapWithAllocator is an example of such.
        mem: std.ArrayListUnmanaged(u8),

        alloc: std.mem.Allocator,

        return_data: []u8,

        // TODO: Specialised allocators later on, perhaps external allocators passed in from host (where we're potentially embedded).
        // pub fn init(alloc: std.mem.Allocator) !Self {
        pub fn init(alloc: std.mem.Allocator, env: *Environment) !Self {
            // var gpa: std.heap.DebugAllocator(.{}) = .init;
            // const allocator = gpa.allocator();

            // var tracing_alloc = tracy.TracingAllocator.init(std.heap.page_allocator);
            // const allocator = tracing_alloc.allocator();

            return Self{
                // .alloc = allocator,
                .alloc = alloc,
                .pc = 0,
                .stack = try std.BoundedArray(WORD, MAX_STACK_DEPTH).init(0),
                .env = env,
                .mem = .empty,
                .return_data = &[0]u8{},
            };
        }

        // TODO: Actually is better as inline?
        inline fn decodeOp(raw_bytecode: u8) OpCode {
            // If we do want to check for further bytecode then we can probably keep using labelled switch and instead would need to store the bytecode on the vm struct, take the ip as a paramete rhere, check we're within bounds and then return as we currently do.
            return @as(OpCode, @enumFromInt(raw_bytecode));
        }

        // JORDAN: Function `digits2` in Zig std/fmt.zig interesting.

        // TODO: Have these as a comptime function which will inline flip the sign instead?

        inline fn asSignedWord(value: WORD) SIGNED_WORD {
            return @as(SIGNED_WORD, @bitCast(value));
        }

        inline fn asUnsignedWord(value: SIGNED_WORD) WORD {
            return @as(WORD, @bitCast(value));
        }

        // XXX: Is this actually useful? Trying to make things clearer.
        inline fn u8Truncate(value: anytype) u8 {
            return @as(u8, @truncate(value));
        }

        pub fn execute(self: *Self, rom: []const u8) !void {
            const zone = tracy.initZone(@src(), .{ .name = "EVM execute" });
            defer zone.deinit();

            print("{s:=^60}\n", .{" EVM execute "});
            // JORDAN: So this labelled switch API is nice but makes adding disassemly and debug information more verbose vs. a while loop over the rom which can invoke any such logic in one-ish place. Beyond inline functions at comptime based on build flags (i.e. if debug build, inline some debug functions) runtime debugging would require a check at every callsite for debug output I think. Is this the cost to pay? Tradeoffs etc.
            _ = sw: switch (decodeOp(rom[self.pc])) {
                .STOP => |op| {
                    const zone_stop = tracy.initZone(@src(), .{ .name = "OP: STOP" });
                    defer zone_stop.deinit();

                    tracy.message("STOP executed");

                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // TODO: Here and for other halt opcodes return with error union so we can execute appropriate post-halt actions.
                    return;
                },
                .ADD => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // TODO: Here and for other similar log with traceStackTake

                    // TODO: Here and elsewhere with simpler modulo logic is this compiled to a bitwise AND? (and for others as appropriate). Use of this form involves peer type resolution so any overheads etc need to be investigated.
                    try self.stack.append(self.stack.pop().? +% self.stack.pop().?);

                    continue :sw decodeOp(rom[self.pc]);
                },
                .MUL => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    try self.stack.append(self.stack.pop().? *% self.stack.pop().?);

                    continue :sw decodeOp(rom[self.pc]);
                },
                .SUB => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    try self.stack.append(self.stack.pop().? -% self.stack.pop().?);

                    continue :sw decodeOp(rom[self.pc]);
                },
                .DIV => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] = numerator ; s[1] = denominator.
                    const numerator = self.stack.pop().?;
                    const denominator = self.stack.pop().?;

                    // Stack items are unsigned-integers, Zig will do floored division automatically.
                    try self.stack.append(if (denominator == 0) 0 else (numerator / denominator));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .SDIV => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] = numerator ; s[1] = denominator.
                    // Both values treated as 2's complement signed 256-bit integers.
                    const numerator: i256 = @bitCast(self.stack.pop().?);
                    const denominator: i256 = @bitCast(self.stack.pop().?);

                    if (denominator == 0) {
                        try self.stack.append(0);
                        continue :sw decodeOp(rom[self.pc]);
                    }

                    // TODO: This can be optimised probably, look into it later. For example, before bit-casting we can perform the equivalent checks for -1 and -2^255 by checking for max u256 (i.e. all bits set, which is -1 in two's complement for i256) and whether only the first bit is set as that's maximum negative.

                    try self.stack.append(@bitCast(if (denominator == -1 and numerator == std.math.minInt(i256)) std.math.minInt(i256) else @divTrunc(numerator, denominator)));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .MOD => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] = numerator ; s[1] = denominator.
                    const numerator = self.stack.pop().?;
                    const denominator = self.stack.pop().?;

                    // Stack items are unsigned-integers, Zig will do floored division automatically.
                    try self.stack.append(if (denominator == 0) 0 else (numerator % denominator));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .SMOD => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] = numerator ; s[1] = denominator.
                    // Both values treated as 2's complement signed 256-bit integers.
                    const numerator: i256 = @bitCast(self.stack.pop().?);
                    const denominator: i256 = @bitCast(self.stack.pop().?);

                    try self.stack.append(if (denominator == 0) 0 else @bitCast(@rem(numerator, denominator)));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .ADDMOD => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0, 1] = addition operands ; s[2] = denominator.
                    // TODO: Definitely a nicer way of implementing this outside of u257 and an intCast; optimise for that later.

                    const left: u257 = self.stack.pop().?;
                    const right = self.stack.pop().?;
                    const denominator = self.stack.pop().?;

                    if (denominator == 0) {
                        try self.stack.append(0);
                        continue :sw decodeOp(rom[self.pc]);
                    }

                    const result: u256 = @intCast((left + right) % denominator);
                    try self.stack.append(result);

                    continue :sw decodeOp(rom[self.pc]);
                },
                .MULMOD => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0, 1] = addition operands ; s[2] = denominator.
                    // TODO: Ditto on modulo optimisation.
                    const left: u512 = self.stack.pop().?;
                    const right = self.stack.pop().?;
                    const denominator = self.stack.pop().?;

                    if (denominator == 0) {
                        try self.stack.append(0);
                        continue :sw decodeOp(rom[self.pc]);
                    }

                    const result: u256 = @intCast((left * right) % denominator);
                    try self.stack.append(result);

                    continue :sw decodeOp(rom[self.pc]);
                },
                .EXP => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // XXX: Alternative left-to-right binary exponentiation uses one less u512 but requires more bit-twiddling. Consider alternatives / optimise later on.

                    // s[0] = base ; s[1] = exponent.

                    var base: DOUBLE_WORD = self.stack.pop().?;
                    var exponent = self.stack.pop().?;

                    var result: DOUBLE_WORD = 1;

                    // Right-to-left binary exponentiation.
                    while (exponent > 0) : (exponent >>= 1) {
                        if (@as(u1, @truncate(exponent)) == 1) {
                            // result = (result * base) % WORD_MAX;
                            result = @mod(result * base, WORD_MAX);
                        }
                        // base = (base * base) % WORD_MAX;
                        base = @mod(base * base, WORD_MAX);
                    }

                    // Pedantic overflow check; could use @intCast instead.
                    std.debug.assert(result <= WORD_MAX);

                    try self.stack.append(@as(WORD, @truncate(result)));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .SIGNEXTEND => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] = byte size of target value minus one ; s[1] = value

                    // s[1] is read as a two's complement signed integer; if s[1] has a meaningful
                    // byte size of 2 then s[0] is given as 1 since that is s[1]'s meaningful
                    // byte size minus one.

                    // Practically s[0] has a maximum meaningful value of 30 when read from the
                    // stack (2 less than BYTES_IN_WORD which becomes 31, it's real
                    // meaningful-maximum, as we add 1) and if s[0] is above 31 nothing is done to
                    // s[1].

                    // Extension is always done up to WORD size.

                    const bytes = self.stack.pop().? + 1;

                    // There's no room to extend s[1] so we can do nothing.
                    if (bytes > (BYTES_IN_WORD - 1)) {
                        continue :sw decodeOp(rom[self.pc]);
                    }

                    // TODO: Optimise this as needed.
                    const value = self.stack.pop().?;
                    const msb = @as(u1, @truncate(value >> (u8Truncate(bytes) * 8) - 1));

                    // Not a negative two's complement number, nothing to do.
                    if (msb != 1) {
                        try self.stack.append(value);
                        continue :sw decodeOp(rom[self.pc]);
                    }

                    try self.stack.append((WORD_MAX << (u8Truncate(bytes) * 8)) | value);

                    continue :sw decodeOp(rom[self.pc]);
                },
                .LT => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] < s[1]

                    try self.stack.append(@intFromBool(self.stack.pop().? < self.stack.pop().?));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .GT => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] > s[1]

                    try self.stack.append(@intFromBool(self.stack.pop().? > self.stack.pop().?));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .SLT => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] < s[1]

                    // zig fmt: off
                    try self.stack.append(@intFromBool(
                        @as(SIGNED_WORD, @bitCast(self.stack.pop().?))
                            <
                        @as(SIGNED_WORD, @bitCast(self.stack.pop().?))));
                    // zig fmt: on

                    continue :sw decodeOp(rom[self.pc]);
                },
                .SGT => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] > s[1]

                    // zig fmt: off
                    try self.stack.append(@intFromBool(
                        @as(SIGNED_WORD, @bitCast(self.stack.pop().?))
                            >
                        @as(SIGNED_WORD, @bitCast(self.stack.pop().?))));
                    // zig fmt: on

                    continue :sw decodeOp(rom[self.pc]);
                },
                .EQ => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] == s[1]

                    try self.stack.append(@intFromBool(self.stack.pop().? == self.stack.pop().?));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .ISZERO => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] == 0

                    try self.stack.append(@intFromBool(self.stack.pop().? == 0));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .AND => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // Bitwise: s[0] AND s[1]

                    // TODO: A bunch of these kinds of patterns can likely be optimised to just popping one element off, and then setting the top stack element. Optimise after BoundedArray is kept or changed.
                    try self.stack.append(self.stack.pop().? & self.stack.pop().?);

                    continue :sw decodeOp(rom[self.pc]);
                },
                .OR => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // Bitwise: s[0] OR s[1]

                    try self.stack.append(self.stack.pop().? | self.stack.pop().?);

                    continue :sw decodeOp(rom[self.pc]);
                },
                .XOR => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // Bitwise: s[0] XOR s[1]

                    try self.stack.append(self.stack.pop().? ^ self.stack.pop().?);

                    continue :sw decodeOp(rom[self.pc]);
                },
                .NOT => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // Bitwise: NOT s[0]

                    try self.stack.append(~self.stack.pop().?);

                    continue :sw decodeOp(rom[self.pc]);
                },
                .BYTE => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] = byte offset to take from ; s[1] = word value to be sliced

                    const offset = self.stack.pop().?;

                    // s[0] above amount of bytes in WORD, shortcut response to 0.
                    if (offset >= BYTES_IN_WORD) {
                        self.stack.set(self.stack.len - 1, 0);

                        continue :sw decodeOp(rom[self.pc]);
                    }

                    // zig fmt: off
                    self.stack.set(
                        self.stack.len - 1,
                        u8Truncate(
                            self.stack.get(self.stack.len - 1)
                                >>
                            (@as(u8, BITS_IN_WORD - 8) - (u8Truncate(offset) * 8))
                        )
                    );
                    // zig fmt: on

                    continue :sw decodeOp(rom[self.pc]);
                },
                // XXX: For SHL, SHR, SAR: which is faster doing these bitwise shifts or equivalent arithmetic (floor division etc). Optimisation. Need to benchmark the assembly from these and compare it to the "naive" way of doing them (just divisions etc) since LLVM _probably_ does a better job..?
                .SHL => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] = bits to shift by ; s[1] = value to be shifted

                    const bits = self.stack.pop().?;

                    // Trying to shift left over 255 (WORD bits - 1) places shortcut to zero.
                    if (bits >= @typeInfo(WORD).int.bits) {
                        _ = self.stack.pop().?; // XXX: Ripe for top of stack set.
                        try self.stack.append(0);
                        continue :sw decodeOp(rom[self.pc]);
                    }

                    // TODO: u8 being log2(u256) i.e. log2(WORD) is all the reflection on WORD worth it? Idea being maybe someone could (idk why) change WORD to.. u128 but then it wouldn't be the EVM (unless the spec changed) etc.
                    try self.stack.append(self.stack.pop().? << @as(u8, @truncate(bits)));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .SHR => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] = bits to shift by ; s[1] = value to be shifted

                    const bits = self.stack.pop().?;

                    // Trying to shift right over 255 (WORD bits - 1) places shortcut to zero.
                    if (bits >= @typeInfo(WORD).int.bits) {
                        _ = self.stack.pop().?;
                        try self.stack.append(0);
                        continue :sw decodeOp(rom[self.pc]);
                    }

                    try self.stack.append(self.stack.pop().? >> @as(u8, @truncate(bits)));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .SAR => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] = bits to shift by ; s[1] = value to be shifted
                    // s[1] and result pushed to stack are treated as signed; s[0] is unsigned.

                    const bits = self.stack.pop().?;
                    const value = asSignedWord(self.stack.pop().?);

                    // Trying to shift right over 255 (WORD bits - 1) places shortcut...
                    if (bits >= @typeInfo(WORD).int.bits) {
                        switch (value > 0) {
                            // ...positive so 0
                            true => try self.stack.append(0),
                            // ...negative so -1
                            false => try self.stack.append(asUnsignedWord(-1)),
                        }

                        continue :sw decodeOp(rom[self.pc]);
                    }

                    try self.stack.append(asUnsignedWord(value >> @as(u8, @truncate(bits))));

                    continue :sw decodeOp(rom[self.pc]);
                },
                .KECCAK256 => {
                    // TODO: Check zig stdlib or other packages. Also since this isn't a zkEVM make sure any side-channel proections are disabled for any calls to hash.
                },
                .ADDRESS => {
                    // TODO
                },
                .BALANCE => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // in-place replace the content of the balance
                    self.stack.set(self.stack.len - 1, try self.env.getBalance(self.stack.get(self.stack.len - 1)));
                },
                // TODO: ORIGIN to BLOBBASEFEE
                .POP => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    _ = self.stack.pop().?;

                    continue :sw decodeOp(rom[self.pc]);
                },
                .MLOAD => {
                    // TODO
                },
                .MSTORE => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // s[0] = memory offset to write from ; s[1] = value to write

                    const offset = self.stack.pop().?;
                    const value = self.stack.pop().?;

                    // resize memory if need be
                    // NOTE: this should incur some extra gas cost
                    const sum_and_overflow = @addWithOverflow(offset, 32);
                    if (sum_and_overflow[1] == 1) {
                        return error.MemResizeUInt256Overflow;
                    }
                    if (@as(u256, self.mem.items.len) < sum_and_overflow[0]) {
                        const memsize_usize: usize = @truncate(sum_and_overflow[0]);
                        const old_size = self.mem.items.len;
                        // GUILLAUME: Note that this will potentially OOM if the offset is too large.
                        // This is ok, because it's meant to be capped by the gas cost.
                        try self.mem.resize(self.alloc, memsize_usize);
                        @memset(self.mem.items[old_size..@truncate(offset)], 0);
                    }
                    std.mem.writeInt(u256, @ptrCast(self.mem.items[@truncate(offset)..@truncate(offset + 32)]), value, .big);

                    continue :sw decodeOp(rom[self.pc]);
                },
                // TODO: MSTORE8 to MCOPY
                .PUSH0 => |op| {
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    try self.stack.append(0);

                    continue :sw decodeOp(rom[self.pc]);
                },
                // zig fmt: off
                inline .PUSH1,  .PUSH2,  .PUSH3,  .PUSH4,  .PUSH5,  .PUSH6,  .PUSH7,  .PUSH8,
                       .PUSH9,  .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16,
                       .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24,
                       .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32
                // zig fmt: on
                => |op| {
                    traceOp(op, self.pc, .cntln);
                    self.pc += 1;

                    // Offset vs PUSH0 is amount of bytes to read forward and push onto stack as
                    // this instructions operand.
                    const offset = @intFromEnum(op) - @intFromEnum(OpCode.PUSH0);

                    const operand_bytes = rom[self.pc..][0..offset];

                    // std.mem.readInt does not 0-pad types less than requested size, so we construct and reify the `type` we need then upcast to WORD.
                    const operand = @as(WORD, std.mem.readInt(
                        @Type(.{ .int = .{
                            .signedness = .unsigned,
                            .bits = 8 * operand_bytes.len,
                        } }),
                        operand_bytes,
                        .big,
                    ));

                    traceOpPush(self.pc + offset, operand);

                    try self.stack.append(operand);
                    self.pc += offset;

                    continue :sw decodeOp(rom[self.pc]);
                },
                // zig fmt: off
                inline .DUP1, .DUP2,  .DUP3,  .DUP4,  .DUP5,  .DUP6,  .DUP7,  .DUP8,
                       .DUP9, .DUP10, .DUP11, .DUP12, .DUP13, .DUP14, .DUP15, .DUP16
                // zig fmt: on
                => |op| {
                    // TODO: EVM yellowpaper lists very large added/deleted stack items for these, e.g. DUP10 deletes 10 stack items and adds 11. Is that _literally_ happening though, because it doesn't look like it or really make sense if it is.
                    traceOp(op, self.pc, .endln);
                    self.pc += 1;

                    // Offset vs DUP1 is index from top of stack + 1 to duplicate.
                    const offset = 1 + @intFromEnum(op) - @intFromEnum(OpCode.DUP1);

                    try self.stack.append(self.stack.get(self.stack.len - offset));

                    continue :sw decodeOp(rom[self.pc]);
                },
                // zig fmt: off
                inline .SWAP1, .SWAP2,  .SWAP3,  .SWAP4,  .SWAP5,  .SWAP6,  .SWAP7,  .SWAP8,
                       .SWAP9, .SWAP10, .SWAP11, .SWAP12, .SWAP13, .SWAP14, .SWAP15, .SWAP16
                // zig fmt: on
                => {
                    // TODO
                },
                .LOG0 => {
                    // TODO
                },
                // zig fmt: off
                inline .LOG1, .LOG2, .LOG3, .LOG4,
                // zig fmt: on
                => {
                    // TODO
                },
                // TODO: CREATE onwards
                .RETURN, .REVERT => |op| {
                    traceOp(op, self.pc, .endln);

                    // s[0] = memory offset to read from ; s[1] = bytes to read

                    const offset = self.stack.pop().?;
                    const size = self.stack.pop().?;

                    self.return_data = try self.alloc.alloc(u8, @truncate(size));

                    if (offset < self.mem.items.len) {
                        const end = @min(offset + size, self.mem.items.len);

                        @memcpy(self.return_data[0..], self.mem.items[@truncate(offset)..end]);
                    }

                    if (op == .REVERT) return error.Revert;
                    // if (op == .REVERT) return EvmError.Revert;

                    return;
                },
                // TEMPORARY.
                // TODO: Do we want catch unreachable here (in which case make OpCode enum non-exhaustive) or do we want a prong to prevent runtime crashes and log the unhandled opcode. I guess the latter.
                else => {
                    return error.UnknownType;
                },
            };
        }
    };
}

const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();

const DynamicBitSetUnmanaged = std.bit_set.DynamicBitSetUnmanaged;

// TODO: FalsePattern's zig-tracy no-ops its functions if we don't enable it, but also check our own usage is no-op'd when not in-use.
const tracy = @import("tracy");

pub const types = @import("types.zig");
const Transaction = types.Transaction;

const OpModule = @import("op.zig");

const OpCode = OpModule.Enum;
const op_table = OpModule.table;
const OpAnnotation = OpModule.OpAnnotation;
const op_annotation = OpModule.annotation;

const Fee = OpModule.Fee;
const fee_table = OpModule.fee_table;
const GasCost = OpModule.GasCost;

const MAX_STACK_DEPTH = 1024;

const Word = types.Word;
const DoubleWord = types.DoubleWord;
const SignedWord = types.SignedWord;
// const WORD = u256;
// const DOUBLE_WORD = u512;

// const SIGNED_WORD = i256;

const WORD_SIGN_MASK = (1 << @typeInfo(Word).int.bits - 1);

const WORD_MAX: Word = std.math.maxInt(Word);

const BYTES_IN_WORD = @divExact(@typeInfo(Word).int.bits, 8);
const BITS_IN_WORD: u16 = @typeInfo(Word).int.bits;

// TODO: EVM single allocation at start (configurable size or avoid using that strategy). Pass in desired context along with bytecode for easier simulation (e.g. devs, EIPs etc). For now: make a VM with pre-canned bytecode.
// TODO: Scoped logging.

const TraceEndline = enum {
    endln,
    cntln,
};

// XXX: Could have an instruction struct/enum/tagged-union which @calls and inlines some so OP_PUSH3 finds the associated (internal) instruction which has the logic to execute OP_PUSH3 but also things like gas pricing, and any logging. Investigate later, feels too spaghetti for right now.
// TODO: Better interface/implementation or just _stuff_ around tracing; idk. Do later even though it's extremely tempting to hack on cool comptime things now.
fn traceOp(op: OpCode, pc: usize, endline: TraceEndline) void {
    // const decimal_wrapped = std.fmt.comptimePrint("({d})", .{ pc });
    print("{x:0>6}\u{001b}[2m{d:<5}\u{001b}[0m  \u{001b}[2m0x{x:0>2}:\u{001b}[0m{s:<6}{s}", .{ pc, pc, @intFromEnum(op), @tagName(op), if (endline == .endln) "\n" else "\t" });
}

// Meant to print _additional_ information for PUSH1 ... PUSH32.
fn traceOpPush(pc: usize, operand: Word) void {
    print("new_pc={d}, pushed=0x{x}\n", .{ pc, operand });
}

// TODO [2025/08/12]: I had something planned in the past with errors and them having some
//   contextual values (e.g. associated data) but cannot remember right now.
pub const Exception = error{
    StackUnderflow,
    StackOverflow,
    InvalidOp,
    Revert,
    OutOfGas,
    InvalidJumpDestination,
    // XXX: Following are just to shut Zig up for now.
    Overflow, // For: try self.stack.append(self.stack.pop().? +% self.stack.pop().?);
    NotImplemented,
    MemResizeUInt256Overflow,
    OutOfMemory, // For: try self.mem.resize(self.alloc, memsize_usize);
};

// TODO: Output test binary so I can run poop on that.
// TODO: Also for that the container needs access to perf events which it currently does not. Maybe it will need to be built in the container but it can be executed on the VM.
// TODO: Are tag value lookups for enums constant time?

fn traceZone(comptime src: std.builtin.SourceLocation, comptime op: anytype) tracy.ZoneContext {
    // XXX: Would expect compiler to always inline this function, if not and we need to add `inline`.
    const op_reified = switch (@typeInfo(@TypeOf(op))) {
        .pointer => |ptr| blk: {
            // String literals are constant single-item Pointers to null-terminated byte arrays. The type of string literals encodes both the length, and the fact that they are null-terminated.
            if (!(ptr.size == .one and ptr.is_const and ptr.alignment == 1 and ptr.sentinel_ptr == null)) {
                @compileError("Expected a string literal but got " ++ @typeInfo(@TypeOf(op)));
            }

            break :blk op;
        },
        .@"enum" => blk: {
            std.debug.assert(@TypeOf(op) == OpCode);

            break :blk @tagName(op);
        },
        else => @compileError("Expected string literal or OpCode but got " ++ @TypeOf(op)),
    };

    return tracy.initZone(src, .{ .name = op_reified });
}

const PriorOp = struct {
    // TODO: Nicer pattern potentially...?
    annotation: @typeInfo(OpAnnotation).@"struct".fields[0].type,
    pad: usize,
};

pub fn New(comptime Environment: type) type {
    return struct {
        const Self = @This();
        // TODO: ROM context.
        // TODO: Nested EVMs.
        env: *Environment,

        // TODO: Custom data structure for our stack (optimisation).
        /// Machine state: μ_s
        stack: std.BoundedArray(Word, MAX_STACK_DEPTH),

        // TODO: By spec is a u256, cannot use a u256 to address std.BoundedArray as-is. Fix later. This is also means an unsigned pointer-sized integer so it could be very small if the target platform mandates so. Not sure what the concrete solution is right now, perhaps an explicit u256 (or a comptime platform variant) and then a range check during runtime.
        /// Program counter / Instruction pointer.
        pc: usize,

        /// Remaining gas available for executing transaction: T_g
        gas: u64,

        /// Machine state: μ_m, for which 32μ_i is it's length, i.e. length is _bytes_.
        mem: std.ArrayListUnmanaged(u8),

        alloc: std.mem.Allocator,

        return_data: []u8,

        // XXX: I don't like putting this here but it'll do _for now_. If this is never referenced
        //      like the other trace functions when in a debug build (TODO) will this be optimised
        //      out by the Zig compiler and thus reduce the size of this anonymous struct or will
        //      this always bloat the struct size? Logging approach will probably change anyway.
        prior_final: ?PriorOp,

        // TODO: Define an Options struct and take that instead. Perhaps even see if we can get the decl literal .default or .init pattern here. I don't know how that would work with needing to use an allocator though since if we create it in this function it will be invalid once function scope ends. Maybe see if llvm/Builder.zig uses do any of that: https://github.com/ziglang/zig/blob/0.14.0/lib/std/zig/llvm/Builder.zig#L8512
        pub fn init(alloc: std.mem.Allocator, env: *Environment) !Self {
            // var tracing_alloc = tracy.TracingAllocator.init(std.heap.page_allocator);
            // const allocator = tracing_alloc.allocator();

            return Self{
                .alloc = alloc,
                .pc = 0,
                .gas = 0, // Set by Transaction (T_g) at execution time.
                .stack = try std.BoundedArray(Word, MAX_STACK_DEPTH).init(0),
                .env = env,
                .mem = .empty,
                .return_data = &[0]u8{},
                .prior_final = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.mem.deinit(self.alloc);
            self.alloc.free(self.return_data);
        }

        fn nextOp(self: *Self, rom: []const u8) !OpCode {
            // XXX: Validating the stack items here (might) be inefficient as not every opcode requires it (i.e. profile the actual impact) however it is simpler which is better for now (getting zevem working in the first place).
            // XXX: Also if validating stack items here the use of BoundedArray from stdlib is executing potentially useless assertions on presence of items (i.e. .pop() etc) which we could do without if this approach is favoured (i.e. after profiling).
            // const zt = zoneTrace(@src(), "nextOp");
            // defer zt.deinit();
            // defer self.pc += 1;

            if (self.prior_final) |pf| {
                for (pf.annotation) |aa| {
                    print("                {d} <<-- {s:[3]}\u{001b}[2m=\u{001b}[0m{x}\n", .{ aa.index, aa.text, self.stack.get(self.stack.len - aa.index - 1), pf.pad });
                }
            }
            self.prior_final = null;

            // Attempt to access beyond the end of bytecode is a STOP (op 0x00) per spec.
            const raw_bytecode = if (self.pc >= rom.len) return OpCode.STOP else rom[self.pc];

            defer self.pc += 1;

            const opcode = std.meta.intToEnum(OpCode, raw_bytecode) catch return Exception.InvalidOp;
            const opinfo = op_table[raw_bytecode];

            // TODO: Conditionally only execute traceOp if this is a debug build, or has a build argument (e.g. with-tracing or something).
            self.traceOpNew(opcode);

            // Validate stack requirements.
            // TODO: Explicit error set with payload information?
            if (self.stack.len < opinfo.delta) return Exception.StackUnderflow;
            if (MAX_STACK_DEPTH < (self.stack.len - opinfo.delta + opinfo.alpha)) {
                std.debug.print("stackOverflow: stack_len={d}, op_delta={d}, op_alpha={d}\n", .{ self.stack.len, opinfo.delta, opinfo.alpha });

                return Exception.StackOverflow;
            }

            const expanded_memory_words = if (opinfo.memory) |mfn| try mfn(self) else 0;

            // TODO: Get expanded memory size within getAllCosts instead?
            const constant_fee, const dynamic_fee = try getAllCosts(self, opinfo.fee, expanded_memory_words);

            print("  gas=({d}, {d}", .{ constant_fee, dynamic_fee });

            // TODO: Wrap in debug conditional and only get consumeGas once.
            // print("  gas=({d}, {d}", .{ getFee(opinfo.fee.constant), try getCost(self, opinfo.fee) });

            // Consume required gas.
            // self.gas -= try consumeGas(self, opinfo.fee);
            self.gas -= (constant_fee + dynamic_fee);

            // TODO: Wrap in debug conditional.
            print(", {d})\n", .{self.gas});

            // Needs to be after getAllCosts since OutOfGas will trigger before ludicrous integer overflows.
            const expanded_memory_bytes = 32 * expanded_memory_words;

            // TODO (2025/11/13): Could likely optimise this but this is fine for now.
            // Expand memory as required.
            if (expanded_memory_bytes > self.mem.items.len) {
                const current_memory_bytes = self.mem.items.len;
                try self.mem.resize(self.alloc, expanded_memory_bytes);
                @memset(self.mem.items[current_memory_bytes..expanded_memory_bytes], 0);
            }

            // TODO: Wrap in debug conditional.
            // TODO: I forsee a problem with things like SWAP which have huge stack deltas, but
            //       which in reality really don't. The debug info for this as hack-implemented in
            //       op.zig will need a change.
            // Print opinfo delta annotations.
            const annotations = op_annotation.get(opcode) orelse OpAnnotation{
                .delta = &.{},
                .alpha = &.{},
            };

            const pad = blk: {
                var len: usize = 0;
                for (annotations.delta) |d| {
                    if (d.text.len > len) len = d.text.len;
                }
                for (annotations.alpha) |a| {
                    if (a.text.len > len) len = a.text.len;
                }
                break :blk len;
            };

            for (annotations.delta) |ad| {
                // Indexed format argument must come last in tuple otherwise fmt.zig errors.
                print("                {d} -->> {s:[3]}\u{001b}[2m=\u{001b}[0m{x}\n", .{ ad.index, ad.text, self.stack.get(self.stack.len - ad.index - 1), pad });
            }

            // Print opinfo alpha.
            if (annotations.alpha.len > 0) {
                self.prior_final = .{
                    .annotation = annotations.alpha,
                    .pad = pad,
                };
            }

            return opcode;
        }

        // JORDAN: Function `digits2` in Zig std/fmt.zig interesting.

        // TODO: Log everything in logfmt style and have a separate renderer for a disassembly-style display?
        fn traceOpNew(self: *Self, op: OpCode) void {
            const pc_decimal = std.fmt.allocPrint(self.alloc, "({d})", .{self.pc}) catch {
                @panic("out of memory");
            };
            defer self.alloc.free(pc_decimal);

            // Reduced to 4 hex digits (65 535) from 6 (16 777 215) since I imagine the latter
            //   will never practically be sensible in a "print it all out" fashion. As a kind
            //   of hex _explorer_ sure but not for logging... probably.
            // TODO: Plug in real value for nested EVM context number (the hardcoded 0).
            print("{x}:{x:0>4}\u{001b}[2m{s:<5}\u{001b}[0m  \u{001b}[2m{x:0>2}\u{001b}[0m {s:<6}", .{ 0, self.pc, pc_decimal, @intFromEnum(op), @tagName(op) });
        }

        inline fn asSignedWord(value: Word) SignedWord {
            return @as(SignedWord, @bitCast(value));
        }

        inline fn asUnsignedWord(value: SignedWord) Word {
            return @as(Word, @bitCast(value));
        }

        // XXX: Is this actually useful? Trying to make things clearer.
        inline fn u8Truncate(value: anytype) u8 {
            return @as(u8, @truncate(value));
        }

        fn getConstantCost(fee: Fee) u64 {
            // TODO: fee_table on the anon EVM struct so it's dynamic pricing per instance?
            return @intCast(fee_table.get(fee).?);
        }

        fn getDynamicCost(self: *Self, cost: GasCost, memory_size: u64) Exception!u64 {
            return if (cost.dynamic) |dfn| try dfn(self, memory_size) else 0;
        }

        // XXX: Here and above inline functions, remove the `inline` keyword so the compiler can
        //      compute the optimisation itself? Benchmark/optimise.
        fn getAllCosts(self: *Self, cost: GasCost, memory_size: u64) Exception!struct { u64, u64 } {
            const constant_fee = getConstantCost(cost.constant);
            const dynamic_fee = if (getDynamicCost(self, cost, memory_size)) |c| c else |err| return err;

            // TODO: Overflow check?
            if ((constant_fee + dynamic_fee) > self.gas) return Exception.OutOfGas;

            return .{ constant_fee, dynamic_fee };
        }

        pub fn execute(self: *Self, tx: Transaction) Exception!void {
            // TODO (2025/11/13): Likely have to put `tx` onto struct, since when we get into nested execution contexts we still need to report the correct origin (tx.sender).

            const zone = tracy.initZone(@src(), .{ .name = "EVM execute" });
            defer zone.deinit();

            // Print execution information at terminal halting state.
            defer {
                // TODO: return data, stack size, pc (although pc implied from bytecode output)
                print("[HALT]\n\tgas_remaining={d}\n\tgas_consumed={d}\n", .{ self.gas, tx.gas - self.gas });
            }

            print("{s:=^100}\n", .{" EVM execute "});
            // TODO: Print a [CONTEXT] section with gas limit at start.

            self.gas = tx.gas;

            // TODO: The rest of the upfront gas cost per figure 64 of YP.
            if (tx.gas < getConstantCost(.transaction)) return Exception.OutOfGas;

            const g_0 = try getAllCosts(self, .{ .constant = .transaction, .dynamic = null }, 0); // g_0 deduction (TODO: The rest per figure 64).
            self.gas -= (g_0[0] + g_0[1]);

            // TODO: Hack for now, I imagine 'Transaction' type will change soon.
            const rom = tx.data;

            // FIXME: For now fine but see Implementation>Opcodes>JUMP (YP: 9.4.3) we will scan
            //        all of the rom ahead of time and construct a bitmask of valid JUMPDEST
            //        locations which are not within the data portion of any PUSH.
            // FIXME: As I was implementing this I realised we could have an upper bound of u64
            //        since that's what we type the program counter to.. could change to a
            //        simple u64 instead of DynamicBitSetUnmanaged?
            var valid_jumpdests = try DynamicBitSetUnmanaged.initEmpty(self.alloc, rom.len);
            defer valid_jumpdests.deinit(self.alloc);

            // FIXME: Need to pre-scan all bytecode to mark valid JUMPDESTs, unsure if this is
            //        optimisable (halting problem?).
            // FIXME: Better type for length?
            var jdst_pc: usize = 0;
            while (jdst_pc < rom.len) : (jdst_pc += 1) {
                // print("\nidx: {} looking at: {} -- ", .{ jdst_pc, rom[jdst_pc]});
                // const _op = std.meta.intToEnum(OpCode, rom[jdst_pc]) catch return Exception.InvalidOp;
                switch (rom[jdst_pc]) {
                    @intFromEnum(OpCode.JUMPDEST) => {
                        // Valid JUMPDEST, mark.
                        valid_jumpdests.set(jdst_pc);
                    },
                    @intFromEnum(OpCode.PUSH1)...@intFromEnum(OpCode.PUSH32) => |op| {
                        // Skip forward by operand size, same as in main labelled switch.
                        const offset = op - @intFromEnum(OpCode.PUSH0);
                        // print("PUSH, skip forward: {} ", .{ offset });
                        jdst_pc += offset;
                    },
                    else => continue,
                }
            }

            // TODO: Wrap in debug conditional.
            var _iter = valid_jumpdests.iterator(.{});
            print("valid jumpdests ({}):", .{valid_jumpdests.count()});
            while (_iter.next()) |b| {
                print(" {}", .{b});
            }
            print("\n", .{});

            // TODO: Would expect the compiler to pass rom to nextOp as a pointer.
            // print("rom_ptr={*}, rom_ptr_len={*}\n", .{ &rom, &rom.len });

            // JORDAN: So this labelled switch API is nice but makes adding disassemly and debug information more verbose vs. a while loop over the rom which can invoke any such logic in one-ish place. Beyond inline functions at comptime based on build flags (i.e. if debug build, inline some debug functions) runtime debugging would require a check at every callsite for debug output I think. Is this the cost to pay? Tradeoffs etc.
            _ = sw: switch (try self.nextOp(rom)) {
                .STOP => {
                    // const zone_stop = tracy.initZone(@src(), .{ .name = "OP: STOP" });
                    // defer zone_stop.deinit();
                    // tracy.message("STOP executed");

                    // TODO: Here and for other halt opcodes return with error union so we can execute appropriate post-halt actions.
                    return;
                },
                .ADD => {
                    // TODO: Here and for other similar log with traceStackTake

                    // TODO: Here and elsewhere with simpler modulo logic is this compiled to a bitwise AND? (and for others as appropriate). Use of this form involves peer type resolution so any overheads etc need to be investigated.
                    try self.stack.append(self.stack.pop().? +% self.stack.pop().?);

                    continue :sw try self.nextOp(rom);
                },
                .MUL => {
                    try self.stack.append(self.stack.pop().? *% self.stack.pop().?);

                    continue :sw try self.nextOp(rom);
                },
                .SUB => {
                    try self.stack.append(self.stack.pop().? -% self.stack.pop().?);

                    continue :sw try self.nextOp(rom);
                },
                .DIV => {
                    // s[0] = numerator ; s[1] = denominator.
                    const numerator = self.stack.pop().?;
                    const denominator = self.stack.pop().?;

                    // Stack items are unsigned-integers, Zig will do floored division automatically.
                    try self.stack.append(if (denominator == 0) 0 else (numerator / denominator));

                    continue :sw try self.nextOp(rom);
                },
                .SDIV => {
                    // s[0] = numerator ; s[1] = denominator.
                    // Both values treated as 2's complement signed 256-bit integers.
                    const numerator: i256 = @bitCast(self.stack.pop().?);
                    const denominator: i256 = @bitCast(self.stack.pop().?);

                    if (denominator == 0) {
                        try self.stack.append(0);
                        continue :sw try self.nextOp(rom);
                    }

                    // TODO: This can be optimised probably, look into it later. For example, before bit-casting we can perform the equivalent checks for -1 and -2^255 by checking for max u256 (i.e. all bits set, which is -1 in two's complement for i256) and whether only the first bit is set as that's maximum negative.

                    try self.stack.append(@bitCast(if (denominator == -1 and numerator == std.math.minInt(i256)) std.math.minInt(i256) else @divTrunc(numerator, denominator)));

                    continue :sw try self.nextOp(rom);
                },
                .MOD => {
                    // s[0] = numerator ; s[1] = denominator.
                    const numerator = self.stack.pop().?;
                    const denominator = self.stack.pop().?;

                    // Stack items are unsigned-integers, Zig will do floored division automatically.
                    try self.stack.append(if (denominator == 0) 0 else (numerator % denominator));

                    continue :sw try self.nextOp(rom);
                },
                .SMOD => {
                    // s[0] = numerator ; s[1] = denominator.
                    // Both values treated as 2's complement signed 256-bit integers.
                    const numerator: i256 = @bitCast(self.stack.pop().?);
                    const denominator: i256 = @bitCast(self.stack.pop().?);

                    try self.stack.append(if (denominator == 0) 0 else @bitCast(@rem(numerator, denominator)));

                    continue :sw try self.nextOp(rom);
                },
                .ADDMOD => {
                    // s[0, 1] = addition operands ; s[2] = denominator.
                    // TODO: Definitely a nicer way of implementing this outside of u257 and an intCast; optimise for that later.

                    const left: u257 = self.stack.pop().?;
                    const right = self.stack.pop().?;
                    const denominator = self.stack.pop().?;

                    if (denominator == 0) {
                        try self.stack.append(0);
                        continue :sw try self.nextOp(rom);
                    }

                    const result: u256 = @intCast((left + right) % denominator);
                    try self.stack.append(result);

                    continue :sw try self.nextOp(rom);
                },
                .MULMOD => {
                    // s[0, 1] = addition operands ; s[2] = denominator.
                    // TODO: Ditto on modulo optimisation.
                    const left: u512 = self.stack.pop().?;
                    const right = self.stack.pop().?;
                    const denominator = self.stack.pop().?;

                    if (denominator == 0) {
                        try self.stack.append(0);
                        continue :sw try self.nextOp(rom);
                    }

                    const result: u256 = @intCast((left * right) % denominator);
                    try self.stack.append(result);

                    continue :sw try self.nextOp(rom);
                },
                .EXP => {
                    // XXX: Alternative left-to-right binary exponentiation uses one less u512 but requires more bit-twiddling. Consider alternatives / optimise later on.

                    // s[0] = base ; s[1] = exponent.

                    var base: DoubleWord = self.stack.pop().?;
                    var exponent = self.stack.pop().?;

                    var result: DoubleWord = 1;

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

                    try self.stack.append(@as(Word, @truncate(result)));

                    continue :sw try self.nextOp(rom);
                },
                .SIGNEXTEND => {
                    // s[0] = byte size of target value minus one ; s[1] = value

                    // s[1] is read as a two's complement signed integer; if s[1] has a meaningful
                    // byte size of 2 then s[0] is given as 1 since that is s[1]'s meaningful
                    // byte size minus one.

                    // Practically s[0] has a maximum meaningful value of 30 when read from the
                    // stack (2 less than BYTES_IN_WORD which becomes 31, it's real
                    // meaningful-maximum, as we add 1) and if s[0] is above 31 nothing is done to
                    // s[1].

                    // Extension is always done up to Word size.

                    const bytes = self.stack.pop().? + 1;

                    // There's no room to extend s[1] so we can do nothing.
                    if (bytes > (BYTES_IN_WORD - 1)) {
                        continue :sw try self.nextOp(rom);
                    }

                    // TODO: Optimise this as needed.
                    const value = self.stack.pop().?;
                    const msb = @as(u1, @truncate(value >> (u8Truncate(bytes) * 8) - 1));

                    // Not a negative two's complement number, nothing to do.
                    if (msb != 1) {
                        try self.stack.append(value);
                        continue :sw try self.nextOp(rom);
                    }

                    try self.stack.append((WORD_MAX << (u8Truncate(bytes) * 8)) | value);

                    continue :sw try self.nextOp(rom);
                },
                .LT => {
                    // s[0] < s[1]

                    try self.stack.append(@intFromBool(self.stack.pop().? < self.stack.pop().?));

                    continue :sw try self.nextOp(rom);
                },
                .GT => {
                    // s[0] > s[1]

                    try self.stack.append(@intFromBool(self.stack.pop().? > self.stack.pop().?));

                    continue :sw try self.nextOp(rom);
                },
                .SLT => {
                    // s[0] < s[1]

                    // zig fmt: off
                    try self.stack.append(@intFromBool(
                        @as(SignedWord, @bitCast(self.stack.pop().?))
                            <
                        @as(SignedWord, @bitCast(self.stack.pop().?))));
                    // zig fmt: on

                    continue :sw try self.nextOp(rom);
                },
                .SGT => {
                    // s[0] > s[1]

                    // zig fmt: off
                    try self.stack.append(@intFromBool(
                        @as(SignedWord, @bitCast(self.stack.pop().?))
                            >
                        @as(SignedWord, @bitCast(self.stack.pop().?))));
                    // zig fmt: on

                    continue :sw try self.nextOp(rom);
                },
                .EQ => {
                    // s[0] == s[1]
                    try self.stack.append(@intFromBool(self.stack.pop().? == self.stack.pop().?));

                    continue :sw try self.nextOp(rom);
                },
                .ISZERO => {
                    // s[0] == 0
                    try self.stack.append(@intFromBool(self.stack.pop().? == 0));

                    continue :sw try self.nextOp(rom);
                },
                .AND => {
                    // Bitwise: s[0] AND s[1]

                    // TODO: A bunch of these kinds of patterns can likely be optimised to just popping one element off, and then setting the top stack element. Optimise after BoundedArray is kept or changed.
                    try self.stack.append(self.stack.pop().? & self.stack.pop().?);

                    continue :sw try self.nextOp(rom);
                },
                .OR => {
                    // Bitwise: s[0] OR s[1]
                    try self.stack.append(self.stack.pop().? | self.stack.pop().?);

                    continue :sw try self.nextOp(rom);
                },
                .XOR => {
                    // Bitwise: s[0] XOR s[1]
                    try self.stack.append(self.stack.pop().? ^ self.stack.pop().?);

                    continue :sw try self.nextOp(rom);
                },
                .NOT => {
                    // Bitwise: NOT s[0]
                    try self.stack.append(~self.stack.pop().?);

                    continue :sw try self.nextOp(rom);
                },
                .BYTE => {
                    // TODO: Double check this is always removing 2 stack args.
                    // TODO: Double check it's always working from most-significant byte.

                    // s[0] = byte offset to take from ; s[1] = word value to be sliced

                    const offset = self.stack.pop().?;

                    // s[0] above amount of bytes in Word, shortcut response to 0.
                    if (offset >= BYTES_IN_WORD) {
                        self.stack.set(self.stack.len - 1, 0);

                        continue :sw try self.nextOp(rom);
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

                    continue :sw try self.nextOp(rom);
                },
                // XXX: For SHL, SHR, SAR: which is faster doing these bitwise shifts or equivalent arithmetic (floor division etc). Optimisation. Need to benchmark the assembly from these and compare it to the "naive" way of doing them (just divisions etc) since LLVM _probably_ does a better job..?
                .SHL => {
                    // s[0] = bits to shift by ; s[1] = value to be shifted

                    const bits = self.stack.pop().?;

                    // Trying to shift left over 255 (Word bits - 1) places shortcut to zero.
                    if (bits >= @typeInfo(Word).int.bits) {
                        _ = self.stack.pop().?; // XXX: Ripe for top of stack set.
                        try self.stack.append(0);
                        continue :sw try self.nextOp(rom);
                    }

                    // TODO: u8 being log2(u256) i.e. log2(Word) is all the reflection on Word worth it? Idea being maybe someone could (idk why) change Word to.. u128 but then it wouldn't be the EVM (unless the spec changed) etc.
                    try self.stack.append(self.stack.pop().? << @as(u8, @truncate(bits)));

                    continue :sw try self.nextOp(rom);
                },
                .SHR => {
                    // s[0] = bits to shift by ; s[1] = value to be shifted

                    const bits = self.stack.pop().?;

                    // Trying to shift right over 255 (Word bits - 1) places shortcut to zero.
                    if (bits >= @typeInfo(Word).int.bits) {
                        _ = self.stack.pop().?;
                        try self.stack.append(0);
                        continue :sw try self.nextOp(rom);
                    }

                    try self.stack.append(self.stack.pop().? >> @as(u8, @truncate(bits)));

                    continue :sw try self.nextOp(rom);
                },
                .SAR => {
                    // TODO: llvm has an intrinsic for this I believe, use theirs instead? Could be an optimisation for later but then would tie us to llvm.

                    // s[0] = bits to shift by ; s[1] = value to be shifted
                    // s[1] and result pushed to stack are treated as signed; s[0] is unsigned.

                    const bits = self.stack.pop().?;
                    const value = asSignedWord(self.stack.pop().?);

                    // Trying to shift right over 255 (Word bits - 1) places shortcut...
                    if (bits >= @typeInfo(Word).int.bits) {
                        switch (value > 0) {
                            // ...positive so 0
                            true => try self.stack.append(0),
                            // ...negative so -1
                            false => try self.stack.append(asUnsignedWord(-1)),
                        }

                        continue :sw try self.nextOp(rom);
                    }

                    try self.stack.append(asUnsignedWord(value >> @as(u8, @truncate(bits))));

                    continue :sw try self.nextOp(rom);
                },
                .KECCAK256 => {
                    // s[0] = memory offset to read from ; s[1] = length to read

                    // TODO: Since this isn't a zkEVM make sure any side-channel proections are disabled for any calls to hash.

                    // FIXME: Two intCasts to usize for std.mem.items slice, problem or not?
                    const offset: usize = @intCast(self.stack.pop().?);
                    const length: usize = @intCast(self.stack.pop().?);

                    // TODO: Hash directly into the stack instead of this intermediate variable?
                    var digest = [_]u8{0} ** 32;

                    // print("Hashing: {x}\n", .{                        self.mem.items[offset..(offset + length)]});

                    std.crypto.hash.sha3.Keccak256.hash(
                        // Note: The `- 1` in YP is wrong.
                        @ptrCast(self.mem.items[offset..(offset + length)]),
                        &digest,
                        .{},
                    );

                    try self.stack.append(std.mem.readInt(Word, &digest, .big));

                    continue :sw try self.nextOp(rom);
                },
                .ADDRESS => {
                    // TODO
                    return error.NotImplemented;
                },
                .BALANCE => {
                    try self.stack.append(try self.env.getBalance());
                    // TODO: Next op?
                },
                // TODO: Spit as appropriate when implementing.
                .ORIGIN => {
                    try self.stack.append(tx.sender);

                    continue :sw try self.nextOp(rom);
                },
                .CALLER, .CALLVALUE, .CALLDATALOAD, .CALLDATASIZE, .CALLDATACOPY, .CODESIZE, .CODECOPY, .GASPRICE, .EXTCODESIZE, .EXTCODECOPY, .RETURNDATASIZE, .RETURNDATACOPY, .EXTCODEHASH => {
                    // TODO: Implement.
                    return error.NotImplemented;
                },
                .BLOCKHASH => {
                    // TODO: Implement.
                    return error.NotImplemented;
                },
                .COINBASE => {
                    try self.stack.append(self.env.block.beneficiary);

                    continue :sw try self.nextOp(rom);
                },
                .TIMESTAMP => {
                    try self.stack.append(self.env.block.timestamp);

                    continue :sw try self.nextOp(rom);
                },
                .NUMBER => {
                    try self.stack.append(self.env.block.number);

                    continue :sw try self.nextOp(rom);
                },
                .PREVRANDAO => {
                    // TODO: Decide on data type.
                    return error.NotImplemented;
                    // try self.stack.append(self.env.block.randao);

                    // continue :sw try self.nextOp(rom);
                },
                .GASLIMIT => {
                    try self.stack.append(self.env.block.gas_limit);

                    continue :sw try self.nextOp(rom);
                },
                .CHAINID => {
                    // TODO: Implement.
                    return error.NotImplemented;
                },
                .SELFBALANCE => {
                    // TODO: Implement.
                    return error.NotImplemented;
                },
                .BASEFEE => {
                    try self.stack.append(self.env.block.base_fee);

                    return error.NotImplemented;
                },
                .BLOBHASH => {
                    // TODO: gas pricing and opcode notes from eip-4844
                    return error.NotImplemented;
                },
                .BLOBBASEFEE => {
                    // TODO: gas pricing and opcode notes from eip-7516
                    return error.NotImplemented;
                },
                .POP => {
                    _ = self.stack.pop().?;

                    continue :sw try self.nextOp(rom);
                },
                .MLOAD => {
                    // s[0] = memory offset to read from

                    const offset = self.stack.pop().?;

                    try self.stack.append(std.mem.readInt(Word, @ptrCast(self.mem.items[@truncate(offset)..@truncate(offset + 32)]), .big));

                    continue :sw try self.nextOp(rom);
                },
                .MSTORE => {
                    // s[0] = memory offset to write to ; s[1] = value to write

                    const offset = self.stack.pop().?;
                    const value = self.stack.pop().?;

                    std.mem.writeInt(Word, @ptrCast(self.mem.items[@truncate(offset)..@truncate(offset + 32)]), value, .big);

                    continue :sw try self.nextOp(rom);
                },
                .MSTORE8 => {
                    // s[0] = memory address to write to ; s[1] = value mod 256 to write

                    const offset = self.stack.pop().?;
                    const value_raw = self.stack.pop().?;

                    // TODO: Replace '256' with bitsize of Word (which is 256, for 'better' config?)
                    const value_mod: u8 = @intCast(if (value_raw == 0) 0 else (value_raw % 256));

                    std.mem.writeInt(u8, @ptrCast(self.mem.items[@truncate(offset)..@truncate(offset + 1)]), value_mod, .big);

                    continue :sw try self.nextOp(rom);
                },
                .SLOAD, .SSTORE => {
                    // TODO
                    return error.NotImplemented;
                },
                .JUMP => {
                    // s[0] = new program counter value
                    const new_pc: @TypeOf(self.pc) = @intCast(self.stack.pop().?);

                    if (valid_jumpdests.isSet(new_pc) == false) {
                        return Exception.InvalidJumpDestination;
                    }

                    self.pc = new_pc;

                    continue :sw try self.nextOp(rom);
                },
                .JUMPI => {
                    // s[0] = potential new program counter value ; s[1] = check condition
                    const new_pc: @TypeOf(self.pc) = @intCast(self.stack.pop().?);
                    const condition = self.stack.pop().?;

                    // Non-zero condition = set new program counter.
                    if (condition > 0) {
                        if (valid_jumpdests.isSet(new_pc) == false) {
                            return Exception.InvalidJumpDestination;
                        }

                        self.pc = new_pc;
                    }

                    continue :sw try self.nextOp(rom);
                },
                .PC => {
                    try self.stack.append(self.pc - 1);

                    continue :sw try self.nextOp(rom);
                },
                .MSIZE => {
                    try self.stack.append(self.mem.items.len);

                    continue :sw try self.nextOp(rom);
                },
                .GAS => {
                    try self.stack.append(self.gas);

                    continue :sw try self.nextOp(rom);
                },
                .JUMPDEST => {
                    // Does nothing, is a metadata opcode to mark JUMP/JUMPI targets.
                    continue :sw try self.nextOp(rom);
                },
                .TLOAD, .TSTORE => {
                    // TODO: gas pricing and notes on the spec of these two from eip-1153
                    return error.NotImplemented;
                },
                .MCOPY => {
                    // TODO: gas pricing and notes from eip-5656
                    return error.NotImplemented;
                },
                .PUSH0 => {
                    try self.stack.append(0);

                    continue :sw try self.nextOp(rom);
                },
                // zig fmt: off
                inline .PUSH1,  .PUSH2,  .PUSH3,  .PUSH4,  .PUSH5,  .PUSH6,  .PUSH7,  .PUSH8,
                       .PUSH9,  .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16,
                       .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24,
                       .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32
                // zig fmt: on
                => |op| {
                    const zt = traceZone(@src(), "PUSH");
                    zt.text(@tagName(op));
                    defer zt.deinit();

                    // TODO: YP for PUSH1 to PUSH32 defines function c:
                    // "The function c ensures the bytes default to zero if they extend past the limits"
                    // ^^^ Make sure we're doing this. Add a test trying to push outside bytecode range, it should succeed.

                    // Offset vs PUSH0 is amount of bytes to read forward and push onto stack as
                    // this instructions operand.
                    const offset = @intFromEnum(op) - @intFromEnum(OpCode.PUSH0);

                    const operand_bytes = rom[self.pc..][0..offset];

                    // std.mem.readInt does not 0-pad types less than requested size, so we construct and reify the `type` we need then upcast to Word.
                    const operand = @as(Word, std.mem.readInt(
                        @Type(.{ .int = .{
                            .signedness = .unsigned,
                            .bits = 8 * operand_bytes.len,
                        } }),
                        operand_bytes,
                        .big,
                    ));

                    // traceOpPush(self.pc + offset, operand);

                    try self.stack.append(operand);
                    self.pc += offset;

                    continue :sw try self.nextOp(rom);
                },
                // zig fmt: off
                inline .DUP1, .DUP2,  .DUP3,  .DUP4,  .DUP5,  .DUP6,  .DUP7,  .DUP8,
                       .DUP9, .DUP10, .DUP11, .DUP12, .DUP13, .DUP14, .DUP15, .DUP16
                // zig fmt: on
                => |op| {
                    // Offset vs DUP1 is index from top-of-stack +1 to duplicate.
                    const offset = 1 + @intFromEnum(op) - @intFromEnum(OpCode.DUP1);

                    try self.stack.append(self.stack.get(self.stack.len - offset));

                    continue :sw try self.nextOp(rom);
                },
                // zig fmt: off
                inline .SWAP1, .SWAP2,  .SWAP3,  .SWAP4,  .SWAP5,  .SWAP6,  .SWAP7,  .SWAP8,
                       .SWAP9, .SWAP10, .SWAP11, .SWAP12, .SWAP13, .SWAP14, .SWAP15, .SWAP16
                // zig fmt: on
                => |op| {
                    // Offset vs SWAP1 is index from top-of-stack +1 to swap.

                    // TODO: Let compiler optimise or manually do XOR to swap? Benchmark later.
                    const offset = 1 + @intFromEnum(op) - @intFromEnum(OpCode.SWAP1);
                    const prior_top_item = self.stack.get(self.stack.len - 1);

                    // Put offset item at top-of-stack.
                    self.stack.set(
                        self.stack.len - 1,
                        self.stack.get(self.stack.len - offset - 1),
                    );

                    // Put prior top-of-stack item at offset.
                    self.stack.set(
                        self.stack.len - offset - 1,
                        prior_top_item,
                    );

                    continue :sw try self.nextOp(rom);
                },
                // zig fmt: off
                inline .LOG0, .LOG1, .LOG2, .LOG3, .LOG4,
                // zig fmt: on
                => {
                    // TODO: Implement.
                    // TODO: Custom gas (do this one first I reckon, it's fairly simple).
                    return error.NotImplemented;
                },
                // TODO: These are only grouped while un-implemented, split into own prongs as required when implementing.
                .CREATE, .CALL, .CALLCODE, .DELEGATECALL, .CREATE2, .STATICCALL => {
                    // TODO: Implement.
                    // TODO: Custom gas.
                    return error.NotImplemented;
                },
                .RETURN, .REVERT => |op| {
                    // TODO: Dynamic gas for these opcodes.

                    // s[0] = memory offset to read from ; s[1] = bytes to read

                    const offset = self.stack.pop().?;
                    const size = self.stack.pop().?;

                    self.return_data = try self.alloc.alloc(u8, @truncate(size));

                    if (offset < self.mem.items.len) {
                        const end = @min(offset + size, self.mem.items.len);

                        @memcpy(self.return_data[0..], self.mem.items[@truncate(offset)..end]);
                    }

                    if (op == .REVERT) return Exception.Revert;
                    // if (op == .REVERT) return EvmError.Revert;

                    return;
                },
                .INVALID => {
                    // TODO: Implement (but what, double check do we just do nothing or is this an error.. it is called "invalid").
                    // TODO: Instead of nextOp returning error.InvalidOpCode it should set the opcode to .INVALID as spec says this opcode is executed upon its literal encounter or any other invalid opcode.
                    // TODO: Consume all remaining gas.
                    // TODO: State revert to before given bytecode executed.

                    // TODO: Still needs more to finish implementation I think.
                    return Exception.InvalidOp;
                },
                .SELFDESTRUCT => {
                    // TODO: Implement.
                    // TODO: Has dynamic gas see appendix G and its opcode definition H.2
                    return error.NotImplemented;
                },
            };
        }
    };
}

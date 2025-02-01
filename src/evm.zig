const std = @import("std");
const print = std.debug.print;
const OpCode = @import("opcode.zig").OpCode;

const MAX_STACK_DEPTH = 1024;
const WORD = u256;

// TODO: EVM specified big-endian.
// TODO: EVM single allocation at start (configurable size or avoid using that strategy). Pass in desired context along with bytecode for easier simulation (e.g. devs, EIPs etc). For now: make a VM with pre-canned bytecode.
// TODO: Scoped logging.

const TraceEndline = enum {
    endln,
    cntln,
};

// XXX: Could have an instruction struct/enum/tagged-union which @calls and inlines some so OP_PUSH3 finds the associated (internal) instruction which has the logic to execute OP_PUSH3 but also things like gas pricing, and any logging. Investigate later, feels too spaghetti for right now.
// TODO: Better interface/implementation or just _stuff_ around tracing; idk. Do later even though it's extremely tempting to hack on cool comptime things now.
fn traceOp(op: OpCode, ip: usize, endline: TraceEndline) void {
    print("{x:0>6}\u{001b}[2m:{d}\u{001b}[0m  \u{001b}[2m{X:0>2}:\u{001b}[0m{s: <6}{s}", .{ ip, ip, @intFromEnum(op), @tagName(op), if (endline == .endln) "\n" else "\t" });
}

// Meant to print _additional_ information for PUSH1 ... PUSH32.
fn traceOpPush(ip: usize, operand: WORD) void {
    print("new_ip={d}, pushed=0x{X}\n", .{ ip, operand });
}

// Meant to print _additional_ information for opcodes which take 2 items off the stack then put 1 back on.
fn traceStackTake() void {}

pub const EVM = struct {
    const Self = @This();
    // TODO: ROM context.
    // TODO: Nested EVMs.
    // TODO: Gas.

    // TODO: Custom data structure for our stack (optimisation).
    stack: std.BoundedArray(WORD, MAX_STACK_DEPTH),

    /// Instruction pointer.
    // TODO: Best data size for this? u64, technically it can go to u256 right?
    ip: usize,

    // alloc: std.mem.Allocator,

    // TODO: Specialised allocators later on, perhaps external allocators passed in from host (where we're potentially embedded).
    // pub fn init(alloc: std.mem.Allocator) !Self {
    pub fn init() !Self {
        // var gpa = std.heap.GeneralPurposeAllocator(.{}){};

        return Self{
            // TODO:
            // .alloc = gpa.allocator(),
            .ip = 0,
            .stack = try std.BoundedArray(WORD, MAX_STACK_DEPTH).init(0),
        };
    }

    // TODO: Actually is better as inline?
    inline fn decodeOp(raw_bytecode: u8) OpCode {
        // If we do want to check for further bytecode then we can probably keep using labelled switch and instead would need to store the bytecode on the vm struct, take the ip as a paramete rhere, check we're within bounds and then return as we currently do.
        return @as(OpCode, @enumFromInt(raw_bytecode));
    }

    // JORDAN: Function `digits2` in Zig std/fmt.zig interesting.

    pub fn execute(self: *EVM, rom: []const u8) !void {
        print("{s:=^32}\n", .{" EVM execute "});
        // JORDAN: So this labelled switch API is nice but makes adding disassemly and debug information more verbose vs. a while loop over the rom which can invoke any such logic in one-ish place. Beyond inline functions at comptime based on build flags (i.e. if debug build, inline some debug functions) runtime debugging would require a check at every callsite for debug output I think. Is this the cost to pay? Tradeoffs etc.
        // JORDAN: Unsure if EVM spec __requires__ valid programs specify the bytecode for termination (e.g. 00 for stop, or f3 for return) or if at the end of bytecode the value at the top of the stack is valid. Another way of thinking about this is: how do we deal with running out of bytecode while we're NOT on a stop, or return opcode. Let our caller handle it? If we need to then we must check before dispatching the next instruction that there is further bytecode. How expensive is doing that in reality? That's an optimisation (and im guessing a nitpicky) one.
        _ = sw: switch (decodeOp(rom[self.ip])) {
            .STOP => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                // TODO: Here and for other halt opcodes return with error union so we can execute appropriate post-halt actions.
                return;
            },
            .ADD => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                // TODO: Here and for other similar log with traceStackTake

                // TODO: Here and elsewhere with simpler modulo logic is this compiled to a bitwise AND? (and for others as appropriate). Use of this form involves peer type resolution so any overheads etc need to be investigated.
                try self.stack.append(self.stack.pop() +% self.stack.pop());

                continue :sw decodeOp(rom[self.ip]);
            },
            .MUL => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                try self.stack.append(self.stack.pop() *% self.stack.pop());

                continue :sw decodeOp(rom[self.ip]);
            },
            .SUB => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                try self.stack.append(self.stack.pop() -% self.stack.pop());

                continue :sw decodeOp(rom[self.ip]);
            },
            .DIV => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                // s[0] = numerator ; s[1] = denominator.
                const numerator = self.stack.pop();
                const denominator = self.stack.pop();

                // Stack items are unsigned-integers, Zig will do floored division automatically.
                try self.stack.append(if (denominator == 0) 0 else (numerator / denominator));

                continue :sw decodeOp(rom[self.ip]);
            },
            .SDIV => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                // s[0] = numerator ; s[1] = denominator.
                // Both values treated as 2's complement signed 256-bit integers.
                const numerator: i256 = @bitCast(self.stack.pop());
                const denominator: i256 = @bitCast(self.stack.pop());

                if (denominator == 0) {
                    try self.stack.append(0);
                    continue :sw decodeOp(rom[self.ip]);
                }

                // TODO: This can be optimised probably, look into it later. For example, before bit-casting we can perform the equivalent checks for -1 and -2^255 by checking for max u256 (i.e. all bits set, which is -1 in two's complement for i256) and whether only the first bit is set as that's maximum negative.

                try self.stack.append(@bitCast(if (denominator == -1 and numerator == std.math.minInt(i256)) std.math.minInt(i256) else @divTrunc(numerator, denominator)));

                continue :sw decodeOp(rom[self.ip]);
            },
            .MOD => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                // s[0] = numerator ; s[1] = denominator.
                const numerator = self.stack.pop();
                const denominator = self.stack.pop();

                // Stack items are unsigned-integers, Zig will do floored division automatically.
                try self.stack.append(if (denominator == 0) 0 else (numerator % denominator));

                continue :sw decodeOp(rom[self.ip]);
            },
            .SMOD => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                // s[0] = numerator ; s[1] = denominator.
                // Both values treated as 2's complement signed 256-bit integers.
                const numerator: i256 = @bitCast(self.stack.pop());
                const denominator: i256 = @bitCast(self.stack.pop());

                try self.stack.append(if (denominator == 0) 0 else @bitCast(@rem(numerator, denominator)));

                continue :sw decodeOp(rom[self.ip]);
            },
            .ADDMOD => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                // s[0, 1] = addition operands ; s[2] = denominator.
                // TODO: Definitely a nicer way of implementing this outside of u257 and an intCast; optimise for that later.

                const left: u257 = self.stack.pop();
                const right = self.stack.pop();
                const denominator = self.stack.pop();

                if (denominator == 0) {
                    try self.stack.append(0);
                    continue :sw decodeOp(rom[self.ip]);
                }

                const result: u256 = @intCast((left + right) % denominator);
                try self.stack.append(result);

                continue :sw decodeOp(rom[self.ip]);
            },
            .MULMOD => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                // s[0, 1] = addition operands ; s[2] = denominator.
                // TODO: Ditto on modulo optimisation.
                const left: u512 = self.stack.pop();
                const right = self.stack.pop();
                const denominator = self.stack.pop();

                if (denominator == 0) {
                    try self.stack.append(0);
                    continue :sw decodeOp(rom[self.ip]);
                }

                const result: u256 = @intCast((left * right) % denominator);
                try self.stack.append(result);

                continue :sw decodeOp(rom[self.ip]);
            },
            .EXP => {},
            .SIGNEXTEND => {},
            .LT => {},
            .GT => {},
            .SLT => {},
            .SGT => {},
            .EQ => {},
            .ISZERO => {},
            .AND => {},
            .OR => {},
            .XOR => {},
            .NOT => {},
            .BYTE => {},
            .SHL => {},
            .SHR => {},
            .SAR => {},
            .KECCAK256 => {},
            //
            // TODO: From op ADDRESS onwards
            //
            .PUSH0 => |op| {
                traceOp(op, self.ip, .endln);
                self.ip += 1;

                try self.stack.append(0);

                continue :sw decodeOp(rom[self.ip]);
            },
            // TODO: I don't think ranges over enums are allowed here, can check later (simple example file elsewhere) not that important right now. It is funny that I end up unrolling this manually though.
            // zig fmt: off
            inline .PUSH1,  .PUSH2,  .PUSH3,  .PUSH4,  .PUSH5,  .PUSH6,  .PUSH7,  .PUSH8,
                   .PUSH9,  .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16,
                   .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24,
                   .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32
            // zig fmt: on
            => |op| {
                traceOp(op, self.ip, .cntln);
                self.ip += 1;

                // Offset vs PUSH0 is amount of bytes to read forward and push onto stack as
                // this instructions operand.
                const offset = @intFromEnum(op) - @intFromEnum(OpCode.PUSH0);

                const operand_bytes = rom[self.ip..][0..offset];

                // std.mem.readInt does not 0-pad types less than requested size, so we construct and reify the `type` we need then upcast to WORD.
                const operand = @as(WORD, std.mem.readInt(
                    @Type(.{ .int = .{
                        .signedness = .unsigned,
                        .bits = 8 * operand_bytes.len,
                    } }),
                    operand_bytes,
                    .big,
                ));

                // This is a new line.

                traceOpPush(self.ip + offset, operand);

                try self.stack.append(operand);
                self.ip += offset;

                continue :sw decodeOp(rom[self.ip]);
            },
            // TEMPORARY.
            // TODO: Do we want catch unreachable here (in which case make OpCode enum non-exhaustive) or do we want a prong to prevent runtime crashes and log the unhandled opcode. I guess the latter.
            else => {
                return error.UnknownType;
            },
        };
    }
};

const std = @import("std");
const print = std.debug.print;
const OpCode = @import("opcode.zig").OpCode;

const MAX_STACK_DEPTH = 1024;
const WORD = u256;

// TODO: EVM specified big-endian.
// TODO: EVM single allocation at start (configurable size or avoid using that strategy). Pass in desired context along with bytecode for easier simulation (e.g. devs, EIPs etc). For now: make a VM with pre-canned bytecode.


// TODO: Place these elsewhere, perhaps use a better implementation pattern, and also need to eventually decide on some debug logging framework or is keeping this stuff inline fine.
fn debugLogBasic(op: OpCode, ip: usize) void {
    print("{x:0>6}  {s: <6} {X:0>2}\n", .{ ip, @tagName(op), @intFromEnum(op) });
}

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
        return @as(OpCode, @enumFromInt(raw_bytecode));
    }

    pub fn execute(self: *EVM, rom: []const u8) !void {
        // JORDAN: So this labelled switch API is nice but makes adding disassemly and debug information more verbose vs. a while loop over the rom which can invoke any such logic in one-ish place. Beyond inline functions at comptime based on build flags (i.e. if debug build, inline some debug functions) runtime debugging would require a check at every callsite for debug output I think. Is this the cost to pay? Tradeoffs etc.
        _ = sw: switch (decodeOp(rom[self.ip])) {
            .STOP => {
                debugLogBasic(decodeOp(rom[self.ip]), self.ip);
                self.ip += 1;

                // TODO: Here and for other halt opcodes return with error union so we can execute appropriate post-halt actions.
                return;
            },
            .ADD => {
                debugLogBasic(decodeOp(rom[self.ip]), self.ip);
                self.ip += 1;

                try self.stack.append(self.stack.pop() +% self.stack.pop());
                print("----> {}\n", .{self.stack.pop()});

                continue :sw decodeOp(rom[self.ip]);
            },
            .MUL => {
                print("Multiplying\n", .{});

                try self.stack.append(self.stack.pop() * self.stack.pop());

                self.ip += 1;
                continue :sw decodeOp(rom[self.ip]);
            },
            .SUB => {},
            .DIV => {},
            .SDIV => {},
            .MOD => {},
            .SMOD => {},
            .ADDMOD => {},
            .MULMOD => {},
            .EXP => {},
            .SIGNEXTEND => {},
            // TODO: I don't think ranges over enums are allowed here, can check later (simple example file elsewhere) not that important right now. It is funny that I end up unrolling this manually though.
            .PUSH0 => |op| {
                debugLogBasic(op, self.ip);
                self.ip += 1;

                try self.stack.append(0);

                continue :sw decodeOp(rom[self.ip]);
            },
            inline .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5 => |op| {
                debugLogBasic(op, self.ip);
                self.ip += 1;

                const offset = @intFromEnum(op) - @intFromEnum(OpCode.PUSH0);

                // XXX: Works fine if hardcoded offset value is '32' as a conincidence because 32 u8s = a u256.
                // try self.stack.append(std.mem.readInt(u256, rom[self.ip..][0..32], .big));
                try self.stack.append(std.mem.readInt(u256, rom[self.ip..][0..offset], .big));

                self.ip += offset;

                continue :sw decodeOp(rom[self.ip]);
            },
            // XXX: Non-inline attempt here.
          //   .PUSH1,
          //   .PUSH2,
          //   .PUSH3,
          //   .PUSH4,
          //   .PUSH5,
        // .PUSH6,
          //   .PUSH7,
          //.PUSH8,
          //   .PUSH9,
          //   .PUSH10,
          // .PUSH11,
          //   .PUSH12,
          //   .PUSH13,
          //   .PUSH14,
          //   .PUSH15,
          //   .PUSH16,
          //   .PUSH17,
          //   .PUSH18,
          //   .PUSH19,
          //   .PUSH20,
          //   .PUSH21,
          //   .PUSH22,
          //   .PUSH23,
          //   .PUSH24,
          //   .PUSH25,
          //   .PUSH26,
          //   .PUSH27,
          //   .PUSH28,
          //   .PUSH29,
          //   .PUSH30,
          //   .PUSH31,
          //   .PUSH32 => |op| {
          //       debugLogBasic(op, self.ip);
          //       self.ip += 1;

          //       const offset = @intFromEnum(op) - @intFromEnum(OpCode.PUSH0);

          //       // try self.stack.append(std.mem.readInt(u256, rom[self.ip..][0..32], .big));
          //       try self.stack.append(std.mem.readInt(u256, rom[self.ip..][0..offset], .big));
          //       self.ip += offset;

          //       continue :sw decodeOp(rom[self.ip]);
          //   },
            // TEMPORARY.
            // TODO: Do we want catch unreachable here (in which case make OpCode enum non-exhaustive) or do we want a prong to prevent runtime crashes and log the unhandled opcode. I guess the latter.
            else => {
                return error.UnknownType;
                // return;
            },
        };
    }
};

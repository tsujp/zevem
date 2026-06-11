//! Integration test: run vendored execution-spec-tests fixtures end to end
//! (parse, state transition, zevem execution, post-state verification).
//!
//! The files under testdata/ are verbatim test cases extracted from the
//! pinned EEST release (see spec/README.org for provenance), chosen because
//! zevem can execute them fully today; they must always pass. Broader
//! conformance runs use `just fetch-fixtures` + `just spec` against the
//! complete release.

const std = @import("std");

const fixture = @import("fixture.zig");
const runner = @import("runner.zig");

const vendored = [_][]const u8{
    // Pure stack-op execution ending in an exceptional halt; exercises EVM
    // invocation and all-gas-consumed accounting.
    @embedFile("testdata/stack_underflow.json"),
    // Access-list transactions with exactly-enough and not-enough intrinsic
    // gas; exercises validation, access list gas, and the rejection path.
    @embedFile("testdata/transaction_intrinsic_gas_cost.json"),
};

test "vendored fixtures pass" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var pass: usize = 0;
    var pass_exception: usize = 0;

    for (vendored) |bytes| {
        const cases = try fixture.parseSlice(alloc, bytes);

        for (cases) |case| {
            var results = std.ArrayListUnmanaged(runner.EntryResult).empty;
            try runner.runCase(alloc, case, "Cancun", &results);

            for (results.items) |result| {
                switch (result.outcome) {
                    .pass => pass += 1,
                    .pass_exception => pass_exception += 1,
                    .skip => |reason| {
                        std.debug.print("vendored fixture skipped: {s} [{d}]: {s}\n", .{ result.case_name, result.entry_index, reason.describe() });
                        return error.VendoredFixtureSkipped;
                    },
                    .fail => |message| {
                        std.debug.print("vendored fixture failed: {s} [{d}]\n{s}\n", .{ result.case_name, result.entry_index, message });
                        return error.VendoredFixtureFailed;
                    },
                }
            }
        }
    }

    // Both the executed and the expected-rejection paths must be covered.
    try std.testing.expect(pass > 0);
    try std.testing.expect(pass_exception > 0);
}

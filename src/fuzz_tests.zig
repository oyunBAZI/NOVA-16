//! Bounded parsers/device/debugger targets shared by deterministic smoke and
//! Zig's coverage-guided Smith runner. Never consume host files or wall time.
const std = @import("std");
const Machine = @import("core/machine.zig").Machine;
const rom = @import("rom/format.zig");
const snapshot = @import("core/snapshot.zig");
const assembler = @import("asm/assembler.zig");
const Debugger = @import("debug/debugger.zig").Debugger;
const runtime = @import("core/runtime.zig");
pub fn exercise(a: std.mem.Allocator, data: []const u8) !void {
    if (data.len == 0) return;
    switch (data[0] % 7) {
        0 => {
            _ = rom.parse(data[1..]) catch {};
        },
        1 => {
            var diag: assembler.Diagnostic = .{};
            if (assembler.assemble(a, data[1..], &diag)) |result| result.deinit() else |_| {}
        },
        2 => {
            var m: Machine = .{};
            m.bus.bytes[0xe000] = 1;
            var d: Debugger = .{ .machine = &m, .recorder = .{ .allocator = a } };
            defer d.deinit();
            // Keep output and execution bounded even for syntactically valid commands.
            var bytes: [4096]u8 = undefined;
            var out = std.Io.Writer.fixed(&bytes);
            _ = d.command(data[1..], &out) catch {};
        },
        3 => {
            if (runtime.parseSchedule(a, data[1..])) |events| a.free(events) else |_| {}
        },
        4 => {
            var m: Machine = .{};
            const saved = try snapshot.encode(a, &m);
            defer a.free(saved);
            for (data[1..], 0..) |value, k| saved[32 + (k * 257) % snapshot.payload_size] ^= value;
            // Recompute CRC to reach semantic validation, not only checksum rejection.
            std.mem.writeInt(u32, saved[12..16], std.hash.Crc32.hash(saved[32..]), .little);
            snapshot.restore(&m, saved, null) catch {};
            for (0..32) |_| {
                m.step();
                if (m.cpu.halted or m.cpu.paused or m.cpu.trap != null) break;
            }
        },
        5 => {
            var m: Machine = .{};
            const source = data[1..];
            @memcpy(m.bus.bytes[0xe000..][0..source.len], source);
            for (0..64) |_| {
                m.step();
                if (m.cpu.halted or m.cpu.paused or m.cpu.trap != null) break;
            }
        },
        6 => {
            const input = try std.fmt.allocPrint(a, ".equ a, {s}\n.entry start\nstart: LDI R0, a\nHALT", .{data[1..]});
            defer a.free(input);
            var diag: assembler.Diagnostic = .{};
            if (assembler.assemble(a, input, &diag)) |result| result.deinit() else |_| {}
        },
        else => unreachable,
    }
}
fn guided(_: void, smith: *std.testing.Smith) !void {
    var data: [256]u8 = undefined;
    const len = smith.value(u8);
    smith.bytes(data[0..len]);
    try exercise(std.testing.allocator, data[0..len]);
}
test "coverage guided bounded machine toolchain and snapshot inputs" {
    try std.testing.fuzz({}, guided, .{ .corpus = &.{ "\x01.entry missing\nHALT", "\x02frame 1", "\x03 0 16\n1 0", "\x04seed", "\x05\x01\x00" } });
}
test "deterministic malformed input smoke across all seven target families" {
    var random = std.Random.DefaultPrng.init(0x4e313653);
    var bytes: [256]u8 = undefined;
    for (0..1000) |k| {
        random.random().bytes(&bytes);
        bytes[0] = @intCast(k % 7);
        try exercise(std.testing.allocator, bytes[0..random.random().intRangeAtMost(usize, 1, bytes.len)]);
    }
}
test "allocation failures in assembler outputs and source maps do not leak" {
    const Check = struct {
        fn run(a: std.mem.Allocator) !void {
            var diagnostic: assembler.Diagnostic = .{};
            const result = try assembler.assemble(a, ".entry end\nLDI R0, end\nend: HALT", &diagnostic);
            defer result.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}

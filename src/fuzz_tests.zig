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
    switch (data[0] % 14) {
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
            if (source.len > 8192) return;
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
        7 => {
            _ = assembler.diagnose(a, data[1..]) catch {};
        },
        8 => {
            var diagnostic: assembler.Diagnostic = .{};
            const compiler = @import("compiler/compiler.zig");
            if (compiler.compile(a, data[1..], &diagnostic)) |result| {
                defer result.deinit();
                var machine: Machine = .{};
                try machine.load(result.program.image);
                for (0..256) |_| {
                    machine.step();
                    if (machine.cpu.halted or machine.cpu.paused or machine.cpu.trap != null) break;
                }
            } else |_| {}
        },
        9 => {
            const maps = @import("debug/symbols.zig");
            if (maps.load(a, data[1..], 0)) |loaded| loaded.deinit() else |_| {}
        },
        10 => {
            const image = try rom.packProfile(a, &.{ 1, 0 }, 0, .v2);
            defer a.free(image);
            for (data[1..], 0..) |byte, i| image[(i * 7) % image.len] ^= byte;
            var m: Machine = .{};
            m.load(image) catch {};
        },
        11 => {
            const image = try rom.packProfile(a, &.{ 1, 0 }, 0, .v2);
            defer a.free(image);
            var m: Machine = .{};
            try m.load(image);
            const saved = try snapshot.encodeChecked(a, &m);
            defer a.free(saved);
            const offsets = [_]usize{ 112, 272, 65856, 67552 };
            const lengths = [_]usize{ 160, 65584, 1696, 128 };
            for (data[1..], 0..) |byte, i| saved[offsets[i % 4] + (i * 257) % lengths[i % 4]] ^= byte;
            for (offsets, lengths, 0..) |offset, len, i| std.mem.writeInt(u32, saved[44 + i * 20 ..][0..4], std.hash.Crc32.hash(saved[offset..][0..len]), .little);
            std.mem.writeInt(u32, saved[12..16], std.hash.Crc32.hash(saved[32..]), .little);
            snapshot.restore(&m, saved, m.checksum) catch {};
            try m.validateState();
            for (0..32) |_| m.step();
        },
        12 => {
            if (data.len <= 1) return;
            const image = try rom.packProfile(a, data[1..], 0, .v2);
            defer a.free(image);
            var m: Machine = .{};
            try m.load(image);
            for (data[1..], 0..) |byte, i| {
                const address: u16 = 0xd900 + @as(u16, @intCast(i % 128));
                if (byte & 1 == 0) m.bus.write16(address, @as(u16, byte) * 257) catch {} else m.bus.write8(address, byte) catch {};
            }
            for (0..64) |_| m.step();
            try m.validateState();
        },
        13 => {
            var diagnostic: assembler.Diagnostic = .{};
            if (assembler.assembleProfile(a, data[1..], &diagnostic, .v2)) |result| result.deinit() else |_| {}
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
    try std.testing.fuzz({}, guided, .{ .corpus = &.{ "\x01.entry missing\nHALT", "\x02frame 1", "\x03 0 16\n1 0", "\x04seed", "\x05\x01\x00", "\x08fn main()->u16{return 7;}", "\x08fn main()->u16{var a:[2]u16;return a[3];}", "\x09{\"schema_version\":3}", "\x0bseed", "\x0c\x06\x00\x08\x00", "\x0dEI\nDI\nIRET" } });
}
test "deterministic malformed input smoke across all fourteen target families" {
    var random = std.Random.DefaultPrng.init(0x4e313653);
    var bytes: [256]u8 = undefined;
    for (0..1000) |k| {
        random.random().bytes(&bytes);
        bytes[0] = @intCast(k % 14);
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

test "allocation failures in recovered diagnostics pending constants and owned JSON maps" {
    const Check = struct {
        fn run(a: std.mem.Allocator) !void {
            var d: assembler.Diagnostic = .{};
            const result = try assembler.assemble(a, ".equ a, b+1\n.equ b, 2\nstart: LDI R0, a\nHALT", &d);
            defer result.deinit();
            var output: std.Io.Writer.Allocating = .init(a);
            defer output.deinit();
            const maps = @import("debug/symbols.zig");
            maps.write(&output.writer, a, result, "main.asm") catch |err| {
                // Allocating writer deliberately erases allocator errors at its
                // generic Writer boundary; translate here for injection testing.
                if (err == error.WriteFailed) return error.OutOfMemory;
                return err;
            };
            const loaded = try maps.load(a, output.written(), std.mem.readInt(u32, result.image[12..16], .little));
            defer loaded.deinit();
            _ = try assembler.diagnose(a, "LDI R8, 0\nLDI R9, 1\nHALT");
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}

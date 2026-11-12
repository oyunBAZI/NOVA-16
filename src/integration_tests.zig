const std = @import("std");
const asm16 = @import("asm/assembler.zig");
const Machine = @import("core/machine.zig").Machine;
const video = @import("devices/video.zig");
const examples = @import("examples");
test "splash assembles boots and produces golden PPM sha256" {
    const a = std.testing.allocator;
    var d: asm16.Diagnostic = .{};
    const r = try asm16.assemble(a, examples.splash, &d);
    defer r.deinit();
    var m: Machine = .{};
    try m.load(r.image);
    for (0..100000) |_| {
        m.step();
        if (m.cpu.halted or m.cpu.trap != null) break;
    }
    try std.testing.expect(m.cpu.halted);
    try std.testing.expect(m.cpu.trap == null);
    const bytes = try video.ppm(a, m.bus.bytes[0xc000..0xd800], &m.bus.palette, m.bus.enabled);
    defer a.free(bytes);
    try std.testing.expectEqual(36878, bytes.len);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    try std.testing.expectEqualStrings("1296533d29754dba185c619f8f87e4437b425deaf23f9297bbbcfffecb7771cb", &std.fmt.bytesToHex(hash, .lower));
}
test "frame runtime deterministic replay input and motion" {
    const a = std.testing.allocator;
    var d: asm16.Diagnostic = .{};
    for ([_][]const u8{ examples.bouncing, examples.paint }) |source| {
        const r = try asm16.assemble(a, source, &d);
        defer r.deinit();
        var m: Machine = .{};
        var replay: Machine = .{};
        try m.load(r.image);
        try replay.load(r.image);
        for (0..140) |f| {
            const bits: u8 = if (f < 20) 24 else if (f < 40) 18 else 0;
            m.frame(bits, 4_000_000);
            replay.frame(bits, 4_000_000);
        }
        try std.testing.expect(m.cpu.trap == null);
        try std.testing.expectEqual(140, m.bus.frame);
        try std.testing.expectEqualSlices(u8, &m.bus.bytes, &replay.bus.bytes);
        try std.testing.expectEqualDeep(m.cpu, replay.cpu);
        try std.testing.expect(m.bus.vblank);
        _ = try m.bus.read8(0xd805);
        try std.testing.expect(!m.bus.vblank);
        if (std.mem.eql(u8, source, examples.bouncing)) {
            try std.testing.expectEqual(16, m.cpu.r[0]);
            try std.testing.expectEqual(44, m.cpu.r[1]);
        } else {
            var idle: Machine = .{};
            try idle.load(r.image);
            for (0..140) |_| idle.frame(0, 4_000_000);
            try std.testing.expect(!std.mem.eql(u8, m.bus.bytes[0xc000..0xd800], idle.bus.bytes[0xc000..0xd800]));
        }
    }
}

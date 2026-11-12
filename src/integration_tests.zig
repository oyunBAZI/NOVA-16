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
    try std.testing.expectEqualStrings("420c5fc58a7f204072d9dd257e24607f2d624f3b31a39c154cf5c8cb0152955c", &std.fmt.bytesToHex(hash, .lower));
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
test "diagnostics ROM success register green frame and golden PPM" {
    const a = std.testing.allocator;
    var d: asm16.Diagnostic = .{};
    const r = try asm16.assemble(a, examples.diagnostics, &d);
    defer r.deinit();
    var m: Machine = .{};
    try m.load(r.image);
    for (0..10) |_| {
        m.frame(0, 200000);
        if (m.cpu.halted) break;
    }
    try std.testing.expect(m.cpu.trap == null);
    try std.testing.expect(m.cpu.halted);
    try std.testing.expectEqual(0x600d, m.cpu.r[7]);
    try std.testing.expectEqual(2, m.cpu.r[6]);
    try std.testing.expectEqual(0xbffe, m.cpu.sp);
    for (m.bus.bytes[0xc000..0xd800]) |v| try std.testing.expectEqual(0xbb, v);
    const bytes = try video.ppm(a, m.bus.bytes[0xc000..0xd800], &m.bus.palette, true);
    defer a.free(bytes);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    try std.testing.expectEqualStrings("b46b81b0ff39fe8e0e92b2ffd76c0107835e577e17d2f1e050adfea043ea3df6", &std.fmt.bytesToHex(hash, .lower));
    // Mutate the first arithmetic input, repack with a valid CRC, and verify failure path.
    const payload = try a.dupe(u8, r.image[32..]);
    defer a.free(payload);
    payload[6] = 0;
    const corrupt = try @import("rom/format.zig").pack(a, payload, 0);
    defer a.free(corrupt);
    try m.load(corrupt);
    for (0..10) |_| {
        m.frame(0, 200000);
        if (m.cpu.halted) break;
    }
    try std.testing.expectEqual(0xdead, m.cpu.r[7]);
    for (m.bus.bytes[0xc000..0xd800]) |v| try std.testing.expectEqual(0x66, v);
}
test "paint obeys draw erase clear and clamps cursor at all boundaries" {
    const a = std.testing.allocator;
    var d: asm16.Diagnostic = .{};
    const r = try asm16.assemble(a, examples.paint, &d);
    defer r.deinit();
    var m: Machine = .{};
    try m.load(r.image);
    m.frame(0, 20_000_000);
    m.frame(16, 20_000_000);
    m.frame(0, 20_000_000);
    try std.testing.expectEqual(15, m.cpu.r[6]);
    m.frame(32, 20_000_000);
    m.frame(0, 20_000_000);
    try std.testing.expectEqual(0, m.cpu.r[6]);
    for (0..150) |_| m.frame(24, 20_000_000);
    try std.testing.expectEqual(127, m.cpu.r[0]);
    m.frame(64, 20_000_000);
    for (0..3) |_| m.frame(0, 20_000_000);
    var nonzero: usize = 0;
    for (m.bus.bytes[0xc000..0xd800]) |v| {
        if (v != 0) nonzero += 1;
    }
    try std.testing.expectEqual(1, nonzero); // Only cursor overlay remains.
    for (0..150) |_| m.frame(5, 20_000_000);
    try std.testing.expectEqual(0, m.cpu.r[0]);
    try std.testing.expectEqual(0, m.cpu.r[1]);
    for (0..150) |_| m.frame(10, 20_000_000);
    try std.testing.expectEqual(127, m.cpu.r[0]);
    try std.testing.expectEqual(95, m.cpu.r[1]);
    try std.testing.expect(m.cpu.trap == null);
}

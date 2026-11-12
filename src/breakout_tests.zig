//! Black-box gameplay on real assembled ISA V1. Host only supplies buttons.
const std = @import("std");
const asm16 = @import("asm/assembler.zig");
const Machine = @import("core/machine.zig").Machine;
const snapshot = @import("core/snapshot.zig");
const examples = @import("examples");
const t = std.testing;
fn word(m: *Machine, offset: u16) u16 {
    return m.bus.read16(0x100 + offset) catch unreachable;
}
fn tick(m: *Machine, input: u8) !void {
    const before = m.cpu.retired;
    m.frame(input, std.math.maxInt(u64));
    try t.expect(m.cpu.trap == null);
    try t.expectEqual(@as(u64, 20000), m.cpu.retired - before);
}
fn boot(m: *Machine, image: []const u8) !void {
    try m.load(image);
    for (0..5) |_| try tick(m, 0);
    try t.expectEqual(0, word(m, 0));
    try tick(m, 64);
    for (0..4) |_| try tick(m, 0);
    try t.expectEqual(1, word(m, 0));
}
test "Breakout real guest title input collisions score victory restart and snapshot replay" {
    const a = t.allocator;
    var d: asm16.Diagnostic = .{};
    const r = try asm16.assemble(a, examples.breakout, &d);
    defer r.deinit();
    try t.expect(r.image.len <= 8224);
    var m: Machine = .{};
    try boot(&m, r.image);
    const paddle = word(&m, 2);
    try tick(&m, 4);
    try t.expectEqual(paddle - 1, word(&m, 2));
    try tick(&m, 8);
    try t.expectEqual(paddle, word(&m, 2));
    const saved = try snapshot.encode(a, &m);
    defer a.free(saved);
    var replay: Machine = .{};
    try snapshot.restore(&replay, saved, m.checksum);
    var walls: usize = 0;
    var paddle_hits: usize = 0;
    var brick_hits: usize = 0;
    var victory = false;
    for (0..3000) |_| {
        const input: u8 = 4; // Fixed, reproducible hold-left winning replay.
        const old_dx = word(&m, 8);
        const old_dy = word(&m, 10);
        const old_score = word(&m, 14);
        const old_lives = word(&m, 12);
        try tick(&m, input);
        try tick(&replay, input);
        try t.expectEqualDeep(m.cpu, replay.cpu);
        try t.expectEqualSlices(u8, &m.bus.bytes, &replay.bus.bytes);
        if (word(&m, 8) != old_dx and (word(&m, 4) == 1 or word(&m, 4) == 62)) walls += 1;
        if (word(&m, 10) == 65535 and old_dy == 1 and word(&m, 6) == 84 and old_lives == word(&m, 12)) paddle_hits += 1;
        if (word(&m, 14) > old_score) {
            brick_hits += 1;
            var alive: u16 = 0;
            for (m.bus.bytes[0x200..0x218]) |v| alive += v;
            try t.expectEqual(alive, word(&m, 16));
            try t.expectEqual(24, alive + word(&m, 14));
        }
        if (word(&m, 0) == 3) {
            victory = true;
            break;
        }
        try t.expectEqual(1, word(&m, 0));
    }
    if (!victory) std.debug.print("game unfinished: mode={d} score={d} remaining={d} x={d} y={d} vx={d} vy={d} paddle={d} lives={d}\n", .{ word(&m, 0), word(&m, 14), word(&m, 16), word(&m, 4), word(&m, 6), word(&m, 8), word(&m, 10), word(&m, 2), word(&m, 12) });
    try t.expect(victory);
    try t.expectEqual(24, word(&m, 14));
    try t.expectEqual(24, brick_hits);
    try t.expect(walls > 0 and paddle_hits > 0);
    // Complete end-screen drawing before restarting through the same Start device.
    for (0..5) |_| try tick(&m, 0);
    try tick(&m, 64);
    for (0..4) |_| try tick(&m, 0);
    try t.expectEqual(1, word(&m, 0));
    try t.expectEqual(3, word(&m, 12));
    try t.expectEqual(0, word(&m, 14));
    try t.expectEqual(24, word(&m, 16));
}
test "Breakout loses three lives without assistance and restarts cleanly" {
    const a = t.allocator;
    var d: asm16.Diagnostic = .{};
    const r = try asm16.assemble(a, examples.breakout, &d);
    defer r.deinit();
    var m: Machine = .{};
    try boot(&m, r.image);
    for (0..3000) |_| {
        try tick(&m, 8);
        if (word(&m, 0) == 2) break;
    }
    try t.expectEqual(2, word(&m, 0));
    try t.expectEqual(0, word(&m, 12));
    for (0..5) |_| try tick(&m, 0);
    try tick(&m, 64);
    for (0..4) |_| try tick(&m, 0);
    try t.expectEqual(1, word(&m, 0));
    try t.expectEqual(3, word(&m, 12));
}

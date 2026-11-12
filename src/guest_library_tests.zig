const std = @import("std");
const assembler = @import("asm/assembler.zig");
const Machine = @import("core/machine.zig").Machine;
const lib = @import("guest");
fn call(name: []const u8, args: [4]u16, input: u8) !Machine {
    const a = std.testing.allocator;
    const program = try std.fmt.allocPrint(a, ".entry start\nstart: LDI R7, 0x8000\nLDI R4, 0x4444\nLDI R5, 0x5555\nLDI R6, 0x6666\nLDI R0, {d}\nLDI R1, {d}\nLDI R2, {d}\nLDI R3, {d}\nCALL {s}\nHALT\n{s}", .{ args[0], args[1], args[2], args[3], name, lib.all });
    defer a.free(program);
    var diagnostic: assembler.Diagnostic = .{};
    const r = assembler.assemble(a, program, &diagnostic) catch |err| {
        std.debug.print("guest library {s} {d}:{d} {s} {s}\n", .{ name, diagnostic.line, diagnostic.column, diagnostic.token, diagnostic.code });
        return err;
    };
    defer r.deinit();
    var m: Machine = .{};
    try m.load(r.image);
    m.injectInput(input);
    for (0..200000) |_| {
        m.step();
        if (m.cpu.halted or m.cpu.trap != null) break;
    }
    try std.testing.expect(m.cpu.halted and m.cpu.trap == null);
    try std.testing.expectEqualSlices(u16, &.{ 0x4444, 0x5555, 0x6666, 0x8000 }, m.cpu.r[4..]);
    try std.testing.expectEqual(0xbffe, m.cpu.sp);
    try std.testing.expectEqual(0, m.cpu.depth);
    return m;
}
test "guest arithmetic division sign edges checked operations and ABI preservation" {
    const t = std.testing;
    for ([_]u16{ 0, 1, 255, 32767, 32768, 65535 }) |numerator| {
        for ([_]u16{ 0, 1, 2, 255, 32768, 65535 }) |denominator| {
            const u = try call("n16_udiv", .{ numerator, denominator, 0, 0 }, 0);
            try t.expectEqual(if (denominator == 0) @as(u16, 1) else 0, u.cpu.r[2]);
            if (denominator != 0) {
                try t.expectEqual(numerator / denominator, u.cpu.r[0]);
                try t.expectEqual(numerator % denominator, u.cpu.r[1]);
                const s = try call("n16_sdiv", .{ numerator, denominator, 0, 0 }, 0);
                const x: i32 = @as(i16, @bitCast(numerator));
                const y: i32 = @as(i16, @bitCast(denominator));
                try t.expectEqual(@as(u16, @truncate(@as(u32, @bitCast(@divTrunc(x, y))))), s.cpu.r[0]);
                try t.expectEqual(@as(u16, @truncate(@as(u32, @bitCast(@rem(x, y))))), s.cpu.r[1]);
            }
        }
    }
    const add = try call("n16_uadd_checked", .{ 65535, 1, 0, 0 }, 0);
    try t.expectEqual(0, add.cpu.r[0]);
    try t.expectEqual(1, add.cpu.r[2]);
    const signed = try call("n16_sadd_checked", .{ 32767, 1, 0, 0 }, 0);
    try t.expectEqual(1, signed.cpu.r[2]);
    const cast = try call("n16_u8_checked", .{ 256, 0, 0, 0 }, 0);
    try t.expectEqual(1, cast.cpu.r[2]);
    const cmp = try call("n16_scmp", .{ 65535, 0, 0, 0 }, 0);
    try t.expectEqual(65535, cmp.cpu.r[0]);
}
test "guest clipped graphics packed pixels palette font and numeric drawing" {
    const t = std.testing;
    const even = try call("n16_pixel", .{ 0, 0, 10, 0 }, 0);
    try t.expectEqual(10, even.bus.bytes[0xc000]);
    const odd = try call("n16_pixel", .{ 127, 95, 11, 0 }, 0);
    try t.expectEqual(0xb0, odd.bus.bytes[0xd7ff]);
    const clipped = try call("n16_pixel", .{ 128, 95, 11, 0 }, 0);
    try t.expectEqual(1, clipped.cpu.r[3]);
    for (clipped.bus.bytes[0xc000..0xd800]) |v| try t.expectEqual(0, v);
    const clear = try call("n16_clear", .{ 9, 0, 0, 0 }, 0);
    for (clear.bus.bytes[0xc000..0xd800]) |v| try t.expectEqual(0x99, v);
    const palette = try call("n16_palette", .{ 2, 11, 22, 33 }, 0);
    try t.expectEqualSlices(u8, &.{ 11, 22, 33 }, palette.bus.palette[6..9]);
    const bad = try call("n16_palette", .{ 2, 11, 256, 33 }, 0);
    try t.expectEqual(1, bad.cpu.r[0]);
    try t.expectEqualSlices(u8, &@import("devices/video.zig").default_palette, &bad.bus.palette);
    _ = try call("n16_rect", .{ 127, 95, 65535, 65535 }, 0);
    _ = try call("n16_glyph", .{ 127, 95, 65, 0 }, 0);
    _ = try call("n16_number", .{ 0, 0, 65535, 0 }, 0);
    const bitmap = try call("n16_bitmap", .{ 0, 0, 0xe000, 0x0202 }, 0);
    try t.expectEqual(0, bitmap.cpu.r[3]);
}
test "guest checked memory arrays runtime input and PRNG" {
    const t = std.testing;
    const store = try call("n16_store_word", .{ 0x100, 0xbeef, 0, 0 }, 0);
    try t.expectEqual(0xef, store.bus.bytes[0x100]);
    for ([_]u16{ 1, 0xd800, 0xe000, 65535 }) |address| {
        const bad = try call("n16_store_word", .{ address, 42, 0, 0 }, 0);
        try t.expectEqual(1, bad.cpu.r[3]);
    }
    const array = try call("n16_array_set", .{ 0x100, 2, 3, 1234 }, 0);
    try t.expectEqual(1234, try @constCast(&array.bus).read16(0x104));
    const bounds = try call("n16_array_set", .{ 0x100, 3, 3, 1234 }, 0);
    try t.expectEqual(1, bounds.cpu.r[3]);
    const copy = try call("n16_memcopy", .{ 0x100, 0xe000, 8, 0 }, 0);
    try t.expectEqualSlices(u8, copy.bus.bytes[0xe000..0xe008], copy.bus.bytes[0x100..0x108]);
    const zero = try call("n16_memzero", .{ 0xc000, 6144, 0, 0 }, 0);
    try t.expectEqual(0, zero.cpu.r[3]);
    const input = try call("n16_input_poll", .{ 0, 0, 0, 0 }, 24);
    try t.expectEqual(24, input.cpu.r[0]);
    try t.expectEqual(24, input.cpu.r[1]);
    const random = try call("n16_random", .{ 1234, 0, 0, 0 }, 0);
    try t.expectEqual(@as(u16, @truncate(@as(u32, 1234) * 25173 + 13849)), random.cpu.r[0]);
    const frame = try call("n16_wait_frame", .{ 65535, 0, 0, 0 }, 0);
    try t.expectEqual(0, frame.cpu.r[0]);
}

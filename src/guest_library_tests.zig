const std = @import("std");
const assembler = @import("asm/assembler.zig");
const Machine = @import("core/machine.zig").Machine;
const lib = @import("guest");
fn call(name: []const u8, args: [4]u16, input: u8) !Machine {
    return callWithSetup(name, args, input, "");
}
fn callWithSetup(name: []const u8, args: [4]u16, input: u8, setup: []const u8) !Machine {
    const a = std.testing.allocator;
    const program = try std.fmt.allocPrint(a, ".entry start\nstart: LDI R7, 0x8000\nLDI R4, 0x4444\nLDI R5, 0x5555\nLDI R6, 0x6666\n{s}\nLDI R0, {d}\nLDI R1, {d}\nLDI R2, {d}\nLDI R3, {d}\nCALL {s}\nHALT\n{s}", .{ setup, args[0], args[1], args[2], args[3], name, lib.all });
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

test "guest checked arithmetic and conversion status vectors execute independently" {
    const Vector = struct { name: []const u8, left: u16, right: u16, result: u16, status: u16 };
    for ([_]Vector{
        .{ .name = "n16_usub_checked", .left = 0, .right = 1, .result = 65535, .status = 1 },
        .{ .name = "n16_ssub_checked", .left = 32768, .right = 1, .result = 32767, .status = 1 },
        .{ .name = "n16_sadd_checked", .left = 65535, .right = 65535, .result = 65534, .status = 0 },
        .{ .name = "n16_uadd_checked", .left = 42, .right = 5, .result = 47, .status = 0 },
        .{ .name = "n16_umul_checked", .left = 255, .right = 257, .result = 65535, .status = 0 },
        .{ .name = "n16_umul_checked", .left = 256, .right = 256, .result = 0, .status = 1 },
        .{ .name = "n16_u8_checked", .left = 255, .right = 0, .result = 255, .status = 0 },
        .{ .name = "n16_unsigned_checked", .left = 65535, .right = 0, .result = 65535, .status = 1 },
        .{ .name = "n16_signed_checked", .left = 32768, .right = 0, .result = 32768, .status = 1 },
        .{ .name = "n16_sdiv", .left = 32768, .right = 65535, .result = 32768, .status = 2 },
        .{ .name = "n16_umod", .left = 65535, .right = 255, .result = 0, .status = 0 },
        .{ .name = "n16_smod", .left = 65529, .right = 3, .result = 65535, .status = 0 },
    }) |v| {
        const m = try call(v.name, .{ v.left, v.right, 0, 0 }, 0);
        try std.testing.expectEqual(v.result, m.cpu.r[0]);
        try std.testing.expectEqual(v.status, m.cpu.r[2]);
    }
    const boolean = try call("n16_bool", .{ 42, 0, 0, 0 }, 0);
    try std.testing.expectEqual(1, boolean.cpu.r[0]);
}

test "guest memory overlapping copies bounds and array reads retain atomicity" {
    const initial = "LDI R0, 0x100\nLDI R1, 0x0201\nSTW R1, [R0]\nADDI R0, 2\nLDI R1, 0x0403\nSTW R1, [R0]\nADDI R0, 2\nLDI R1, 0x0605\nSTW R1, [R0]\nADDI R0, 2\nLDI R1, 0x0807\nSTW R1, [R0]";
    const back = try callWithSetup("n16_memcopy", .{ 0x102, 0x100, 6, 0 }, 0, initial);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 1, 2, 3, 4, 5, 6 }, back.bus.bytes[0x100..0x108]);
    const forward = try callWithSetup("n16_memcopy", .{ 0x100, 0x102, 6, 0 }, 0, initial);
    try std.testing.expectEqualSlices(u8, &.{ 3, 4, 5, 6, 7, 8, 7, 8 }, forward.bus.bytes[0x100..0x108]);
    const reject = try callWithSetup("n16_memcopy", .{ 0x100, 0xfff8, 9, 0 }, 0, initial);
    try std.testing.expectEqual(1, reject.cpu.r[3]);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6, 7, 8 }, reject.bus.bytes[0x100..0x108]);
    const get = try callWithSetup("n16_array_get", .{ 0x100, 1, 2, 0 }, 0, initial);
    try std.testing.expectEqual(0x0403, get.cpu.r[0]);
    for ([_]u16{ 0xfffe, 0xd800 }) |base| {
        const bad = try call("n16_array_get", .{ base, 1, 2, 0 }, 16);
        try std.testing.expectEqual(1, bad.cpu.r[3]);
        try std.testing.expectEqual(16, bad.bus.input.pressed);
    }
    const zero = try callWithSetup("n16_memzero", .{ 0xd7ff, 2, 0, 0 }, 0, "LDI R0,0xd7ff\nLDI R1,170\nSTB R1,[R0]");
    try std.testing.expectEqual(1, zero.cpu.r[3]);
    try std.testing.expectEqual(170, zero.bus.bytes[0xd7ff]);
}

test "guest pixel neighbours clipped rectangles and bitmap pixels have exact bytes" {
    const init = "LDI R0,0xc000\nLDI R1,0xab\nSTB R1,[R0]";
    const even = try callWithSetup("n16_pixel", .{ 0, 0, 4, 0 }, 0, init);
    const odd = try callWithSetup("n16_pixel", .{ 1, 0, 4, 0 }, 0, init);
    try std.testing.expectEqual(0xa4, even.bus.bytes[0xc000]);
    try std.testing.expectEqual(0x4b, odd.bus.bytes[0xc000]);
    const rect = try callWithSetup("n16_rect", .{ 127, 95, 2, 2 }, 0, "LDI R0,224\nLDI R1,9\nSTW R1,[R0]");
    try std.testing.expectEqual(0x90, rect.bus.bytes[0xd7ff]);
    const bitmap = try callWithSetup("n16_bitmap", .{ 0, 0, 256, 0x0202 }, 0, "LDI R0,256\nLDI R1,0x0201\nSTW R1,[R0]\nADDI R0,2\nLDI R1,0x0403\nSTW R1,[R0]");
    try std.testing.expectEqual(0x21, bitmap.bus.bytes[0xc000]);
    try std.testing.expectEqual(0x43, bitmap.bus.bytes[0xc040]);
}

test "guest input release sampling acknowledges only the pressed latch" {
    const m = try callWithSetup("n16_input_poll", .{ 0, 0, 0, 0 }, 16, "LDI R0,226\nLDI R1,48\nSTW R1,[R0]");
    try std.testing.expectEqual(16, m.cpu.r[0]);
    try std.testing.expectEqual(16, m.cpu.r[1]);
    try std.testing.expectEqual(32, m.cpu.r[2]);
    try std.testing.expectEqual(0, m.bus.input.pressed);
    try std.testing.expectEqual(16, m.bus.input.held);
    const counter = try call("n16_counter", .{ 4, 5, 0, 0 }, 0);
    try std.testing.expectEqual(0, counter.cpu.r[0]);
}

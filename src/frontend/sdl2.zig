//! Host-only adapter. SDL layouts/constants are compiled from SDL2's C headers.
const std = @import("std");
const Machine = @import("../core/machine.zig").Machine;
const video = @import("../devices/video.zig");
const Host = opaque {};
const Input = extern struct { held: u32, commands: u32 };
comptime {
    if (@sizeOf(Input) != 8 or @offsetOf(Input, "commands") != 4) @compileError("N16Input ABI mismatch");
}
extern fn n16_sdl_open(c_int) ?*Host;
extern fn n16_sdl_close(*Host) void;
extern fn n16_sdl_error() [*:0]const u8;
extern fn n16_sdl_poll(*Host, *Input) void;
extern fn n16_sdl_present(*Host, [*]const u8, c_int) c_int;
extern fn n16_sdl_clock() u64;
extern fn n16_sdl_pace(u64) void;
extern fn n16_sdl_test_event(*Host, c_int, c_int) c_int;
extern fn n16_sdl_resize(*Host, c_int, c_int) void;
fn check(code: c_int) !void {
    if (code < 0) {
        std.debug.print("SDL2: {s}\n", .{n16_sdl_error()});
        return error.SdlFailure;
    }
}
const Controls = struct {
    paused: bool = false,
    fn apply(self: *Controls, m: *Machine, input: Input) bool {
        if (input.commands & 1 != 0) self.paused = !self.paused;
        if (input.commands & 2 != 0) {
            m.reset();
            self.paused = false;
        }
        return input.commands & 4 != 0;
    }
};
pub fn run(m: *Machine, scale: u32, max_frames: u64, cap: u64) !void {
    const host = n16_sdl_open(@intCast(scale)) orelse {
        try check(-1);
        return error.SdlFailure;
    };
    defer n16_sdl_close(host);
    var pixels: [128 * 96 * 3]u8 = undefined;
    var controls: Controls = .{};
    var frame: u64 = 0;
    while (frame < max_frames and m.cpu.retired < cap) : (frame += 1) {
        const start = n16_sdl_clock();
        var input: Input = undefined;
        n16_sdl_poll(host, &input);
        if (controls.apply(m, input)) return;
        if (!controls.paused and !m.cpu.halted and !m.cpu.paused and m.cpu.trap == null) m.frame(@intCast(input.held), cap);
        video.render(m.bus.bytes[0xc000..0xd800], &m.bus.palette, m.bus.enabled, &pixels);
        try check(n16_sdl_present(host, &pixels, 0));
        n16_sdl_pace(start);
    }
}
/// Uses real SDL event polling and renderer readback, without physical input.
pub fn selfTest(a: std.mem.Allocator) !void {
    if (n16_sdl_open(0)) |bad| {
        n16_sdl_close(bad);
        return error.InvalidScaleAccepted;
    }
    const host = n16_sdl_open(4) orelse {
        try check(-1);
        return error.SdlFailure;
    };
    defer n16_sdl_close(host);
    const examples = @import("examples");
    const assembler = @import("../asm/assembler.zig");
    var pixels: [128 * 96 * 3]u8 = undefined;
    for ([_][]const u8{ examples.splash, examples.bouncing, examples.paint }) |source| {
        var diagnostic: assembler.Diagnostic = .{};
        const result = try assembler.assemble(a, source, &diagnostic);
        defer result.deinit();
        var m: Machine = .{};
        try m.load(result.image);
        for (0..5) |_| m.frame(0, 1_000_000);
        if (m.cpu.trap != null) return error.GuestTrap;
        video.render(m.bus.bytes[0xc000..0xd800], &m.bus.palette, m.bus.enabled, &pixels);
        try check(n16_sdl_present(host, &pixels, 1));
    }
    var input: Input = undefined;
    n16_sdl_poll(host, &input);
    for (0..8) |button| {
        try check(n16_sdl_test_event(host, @intCast(button), 0));
        n16_sdl_poll(host, &input);
        if (input.held != @as(u32, 1) << @as(u5, @intCast(button))) return error.InputMapping;
        try check(n16_sdl_test_event(host, @intCast(button), 1));
        n16_sdl_poll(host, &input);
        if (input.held != 0) return error.KeyRelease;
    }
    var m: Machine = .{};
    var diagnostic: assembler.Diagnostic = .{};
    const paint = try assembler.assemble(a, examples.paint, &diagnostic);
    defer paint.deinit();
    try m.load(paint.image);
    m.frame(0, 1_000_000);
    try check(n16_sdl_test_event(host, 3, 0));
    try check(n16_sdl_test_event(host, 4, 0));
    n16_sdl_poll(host, &input);
    m.frame(@intCast(input.held), 1_000_000);
    // x=65 is odd: paint occupies the high nibble, preserving its left neighbour.
    if (m.cpu.r[0] != 65 or m.cpu.r[6] != 0xf0) return error.GuestPaintInput;
    try check(n16_sdl_test_event(host, 3, 1));
    try check(n16_sdl_test_event(host, 4, 1));
    n16_sdl_poll(host, &input);
    video.render(m.bus.bytes[0xc000..0xd800], &m.bus.palette, m.bus.enabled, &pixels);
    try check(n16_sdl_present(host, &pixels, 1));
    var controls: Controls = .{};
    try check(n16_sdl_test_event(host, 8, 0));
    n16_sdl_poll(host, &input);
    _ = controls.apply(&m, input);
    if (!controls.paused) return error.Pause;
    m.cpu.r[0] = 42;
    try check(n16_sdl_test_event(host, 9, 0));
    n16_sdl_poll(host, &input);
    _ = controls.apply(&m, input);
    if (controls.paused or m.cpu.r[0] != 0) return error.Reset;
    try check(n16_sdl_test_event(host, 4, 0));
    try check(n16_sdl_test_event(host, -2, 0));
    n16_sdl_poll(host, &input);
    if (input.held != 0) return error.FocusRelease;
    try check(n16_sdl_test_event(host, 10, 0));
    n16_sdl_poll(host, &input);
    if (!controls.apply(&m, input)) return error.QuitKey;
    try check(n16_sdl_test_event(host, -1, 0));
    n16_sdl_poll(host, &input);
    if (!controls.apply(&m, input)) return error.WindowClose;
    n16_sdl_resize(host, 640, 512);
    n16_sdl_poll(host, &input);
    try check(n16_sdl_present(host, &pixels, 1));
}

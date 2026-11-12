//! Host-only benchmarks. Timers and allocation never enter the deterministic core.
const std = @import("std");
const builtin = @import("builtin");
const n = @import("nova16");
fn now(io: std.Io) i96 {
    return std.Io.Clock.awake.now(io).nanoseconds;
}
const Sample = struct { name: []const u8, operations: u64, nanoseconds: u64 };
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    var samples: usize = 5;
    var instructions: u64 = 2_000_000;
    var k: usize = 1;
    while (k < args.len) : (k += 2) {
        if (k + 1 >= args.len) return error.MissingOptionValue;
        if (std.mem.eql(u8, args[k], "--samples")) samples = try std.fmt.parseInt(usize, args[k + 1], 0) else if (std.mem.eql(u8, args[k], "--instructions")) instructions = try std.fmt.parseInt(u64, args[k + 1], 0) else return error.UnknownOption;
    }
    if (samples == 0 or samples > 100 or instructions < 1000 or instructions > 1_000_000_000) return error.BenchmarkLimit;
    var diagnostic: n.assembler.Diagnostic = .{};
    const program = try n.assembler.assemble(a, "LDI R0, 1\nloop: ADD R1, R0\nJMP loop", &diagnostic);
    defer program.deinit();
    const m = try a.create(n.Machine);
    m.* = .{};
    try m.load(program.image);
    var results: std.ArrayList(Sample) = .empty;
    var guard: u64 = 0;
    for (0..samples) |_| {
        m.reset();
        var start = now(init.io);
        while (m.cpu.retired < instructions) m.step();
        if (m.cpu.trap != null or m.cpu.r[1] != @as(u16, @truncate(instructions / 2))) return error.CpuBenchmarkMismatch;
        guard +%= m.cpu.r[1];
        try results.append(a, .{ .name = "cpu_instruction", .operations = instructions, .nanoseconds = @intCast(now(init.io) - start) });
        m.reset();
        const frames = @max(1, instructions / n.isa.frame_budget);
        start = now(init.io);
        for (0..frames) |_| m.frame(0, frames * n.isa.frame_budget);
        if (m.cpu.retired != frames * n.isa.frame_budget or m.cpu.trap != null) return error.FrameBenchmarkMismatch;
        try results.append(a, .{ .name = "headless_frame", .operations = frames, .nanoseconds = @intCast(now(init.io) - start) });
        start = now(init.io);
        for (0..10000) |index| {
            m.* = .{};
            m.bus.bytes[index % 49152] = 1;
            std.mem.doNotOptimizeAway(m);
        }
        try results.append(a, .{ .name = "initialize", .operations = 10000, .nanoseconds = @intCast(now(init.io) - start) });
        try m.load(program.image);
        start = now(init.io);
        for (0..10000) |index| {
            m.bus.bytes[index % 49152] = 1;
            m.reset();
            std.mem.doNotOptimizeAway(m);
        }
        try results.append(a, .{ .name = "reset", .operations = 10000, .nanoseconds = @intCast(now(init.io) - start) });
        start = now(init.io);
        for (0..1000) |_| {
            try m.load(program.image);
            std.mem.doNotOptimizeAway(m);
        }
        try results.append(a, .{ .name = "rom_load", .operations = 1000, .nanoseconds = @intCast(now(init.io) - start) });
        start = now(init.io);
        for (0..100) |_| {
            const result = try n.assembler.assemble(std.heap.smp_allocator, @import("examples").splash, &diagnostic);
            guard +%= result.image.len;
            result.deinit();
        }
        try results.append(a, .{ .name = "assemble_splash", .operations = 100, .nanoseconds = @intCast(now(init.io) - start) });
        start = now(init.io);
        for (0..100000) |index| {
            const address: u16 = @intCast((index % 2048) * 2);
            try m.bus.write16(address, @truncate(index));
            guard +%= try m.bus.read16(address);
        }
        try results.append(a, .{ .name = "bus_word_pair", .operations = 100000, .nanoseconds = @intCast(now(init.io) - start) });
        var pixels: [128 * 96 * 3]u8 = undefined;
        start = now(init.io);
        for (0..1000) |index| {
            m.bus.bytes[0xc000 + index % 6144] = @truncate(index);
            n.video.render(m.bus.bytes[0xc000..0xd800], &m.bus.palette, m.bus.enabled, &pixels);
            std.mem.doNotOptimizeAway(&pixels);
        }
        try results.append(a, .{ .name = "video_rgb_frame", .operations = 1000, .nanoseconds = @intCast(now(init.io) - start) });
    }
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    try std.json.Stringify.value(.{ .schema_version = @as(u16, 1), .zig_version = "0.17.1", .optimization = @tagName(builtin.mode), .os = @tagName(builtin.os.tag), .arch = @tagName(builtin.cpu.arch), .cpu_model = builtin.cpu.model.name, .guard = guard, .samples = results.items }, .{}, &out.writer);
    try out.writer.writeByte('\n');
    try std.Io.File.stdout().writeStreamingAll(init.io, out.written());
}

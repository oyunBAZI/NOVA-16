const std = @import("std");
const n = @import("nova16");
const options = @import("options");
pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        std.debug.print("nova16: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn run(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len == 2 and eq(args[1], "--build-info")) {
        const builtin = @import("builtin");
        var out: std.Io.Writer.Allocating = .init(a);
        defer out.deinit();
        try std.json.Stringify.value(.{ .version = n.version, .zig_version = "0.17.1", .isa_version = @as(u16, 1), .rom_version = @as(u16, 1), .optimization = @tagName(builtin.mode), .os = @tagName(builtin.os.tag), .arch = @tagName(builtin.cpu.arch), .cpu_model = builtin.cpu.model.name, .gui = options.gui }, .{}, &out.writer);
        try out.writer.writeByte('\n');
        try std.Io.File.stdout().writeStreamingAll(init.io, out.written());
        return;
    }
    if (args.len == 2 and eq(args[1], "--version")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, n.version ++ "\n");
        return;
    }
    if (args.len == 1 or eq(args[1], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "nova16 inspect ROM [--json]\nnova16 run ROM [--headless|--gui] [--frames N] [--max-instructions N]\n  [--screenshot PATH] [--state-json PATH] [--input SCHEDULE] [--scale N]\n");
        return;
    }
    if (args.len < 3) return error.MissingRomPath;
    const data = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], a, .limited(8225));
    var m: n.Machine = .{};
    try m.load(data);
    if (eq(args[1], "inspect")) {
        const json = args.len == 4 and eq(args[3], "--json");
        if (args.len != 3 and !json) return error.UnexpectedOption;
        var out: std.Io.Writer.Allocating = .init(a);
        defer out.deinit();
        const image = try n.rom.parse(data);
        if (json) {
            try std.json.Stringify.value(.{ .schema_version = @as(u16, 1), .format = "N16R", .rom_version = @as(u16, 1), .isa_version = @as(u16, 1), .payload_bytes = image.payload.len, .entry_offset = image.entry, .entry_address = m.cpu.pc, .crc32 = image.checksum }, .{}, &out.writer);
            try out.writer.writeByte('\n');
        } else try out.writer.print("N16R v1 payload={d} entry=0x{x:0>4} crc32={x:0>8}\n", .{ image.payload.len, m.cpu.pc, image.checksum });
        try std.Io.File.stdout().writeStreamingAll(init.io, out.written());
        return;
    }
    if (!eq(args[1], "run")) return error.UnknownCommand;
    var frames: u64 = 120;
    var cap: u64 = 10_000_000;
    var shot: ?[]const u8 = null;
    var state: ?[]const u8 = null;
    var gui = false;
    var mode = false;
    var scale: u32 = 4;
    var input: ?[]const u8 = null;
    var seen = std.StringHashMap(void).init(a);
    defer seen.deinit();
    var k: usize = 3;
    while (k < args.len) : (k += 1) {
        const opt = args[k];
        if (seen.contains(opt)) return error.DuplicateOption;
        try seen.put(opt, {});
        if (eq(opt, "--headless") or eq(opt, "--gui")) {
            if (mode) return error.MutuallyExclusiveModes;
            mode = true;
            gui = eq(opt, "--gui");
            continue;
        }
        k += 1;
        if (k >= args.len) return error.MissingOptionValue;
        const v = args[k];
        if (eq(opt, "--frames")) frames = try std.fmt.parseInt(u64, v, 0) else if (eq(opt, "--max-instructions")) cap = try std.fmt.parseInt(u64, v, 0) else if (eq(opt, "--scale")) scale = try std.fmt.parseInt(u32, v, 0) else if (eq(opt, "--screenshot")) shot = v else if (eq(opt, "--state-json")) state = v else if (eq(opt, "--input")) input = v else return error.UnknownOption;
    }
    if (scale == 0 or scale > 32 or frames > 1_000_000 or cap == 0) return error.InvalidLimit;
    if (gui and input != null) return error.InputScheduleRequiresHeadless;
    if (!gui and seen.contains("--scale")) return error.ScaleRequiresGui;
    if (gui) {
        if (comptime options.gui) {
            try n.sdl.run(&m, scale, frames, cap);
        } else return error.GuiDisabled_rebuild_with_Dgui_true;
    } else {
        const schedule = if (input) |path| try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(1024 * 1024)) else "";
        const events = try n.runtime.parseSchedule(a, schedule);
        defer a.free(events);
        var input_bits: u8 = 0;
        var event: usize = 0;
        var f: u64 = 0;
        while (f < frames and m.cpu.retired < cap and !m.cpu.halted and !m.cpu.paused and m.cpu.trap == null) : (f += 1) {
            while (event < events.len and events[event].frame == f) : (event += 1) input_bits = events[event].bits;
            m.frame(input_bits, cap);
        }
    }
    if (shot) |path| {
        const bytes = try n.video.ppm(a, m.bus.bytes[0xc000..0xd800], &m.bus.palette, m.bus.enabled);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = bytes });
    }
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    try n.state.json(&out.writer, &m);
    if (state) |path| try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = out.written() });
    try std.Io.File.stdout().writeStreamingAll(init.io, out.written());
    if (m.cpu.trap != null) return error.GuestTrap;
}

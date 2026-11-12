const std = @import("std");
const n = @import("nova16");
pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        std.debug.print("n16dbg: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
fn run(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len < 2 or args.len > 4) return error.Usage_n16dbg_ROM_symbols_PATH;
    const data = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .limited(8225));
    var m: n.Machine = .{};
    try m.load(data);
    const symbol_path = if (args.len == 4 and std.mem.eql(u8, args[2], "--symbols")) args[3] else if (args.len == 2) try std.fmt.allocPrint(a, "{s}.sym", .{args[1][0..(if (std.mem.endsWith(u8, args[1], ".n16")) args[1].len - 4 else args[1].len)]}) else return error.BadArguments;
    const symtext = std.Io.Dir.cwd().readFileAlloc(init.io, symbol_path, a, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => "",
        else => return err,
    };
    const symbols = try n.symbol_map.load(a, symtext, m.checksum);
    defer symbols.deinit();
    var d: n.Debugger = .{ .machine = &m, .symbols = symbols.symbols };
    try std.Io.File.stdout().writeStreamingAll(init.io, "NOVA-16 debugger; help lists commands. Addresses use 0x hexadecimal.\n");
    var line: std.ArrayList(u8) = .empty;
    while (true) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "n16> ");
        line.clearRetainingCapacity();
        var too_long = false;
        while (true) {
            var byte: [1]u8 = undefined;
            const got = try std.Io.File.stdin().readStreaming(init.io, &.{&byte});
            if (got == 0) {
                if (line.items.len == 0) return;
                break;
            }
            if (byte[0] == '\n') break;
            if (line.items.len < 4096) try line.append(a, byte[0]) else too_long = true;
        }
        if (too_long) {
            try std.Io.File.stdout().writeStreamingAll(init.io, "error: command too long\n");
            continue;
        }
        var out: std.Io.Writer.Allocating = .init(a);
        defer out.deinit();
        const action = d.command(line.items, &out.writer) catch |err| {
            try out.writer.print("error: {s}\n", .{@errorName(err)});
            try std.Io.File.stdout().writeStreamingAll(init.io, out.written());
            continue;
        };
        switch (action) {
            .none => {},
            .quit => return,
            .saveframe => |path| {
                const bytes = try n.video.ppm(a, m.bus.bytes[0xc000..0xd800], &m.bus.palette, m.bus.enabled);
                defer a.free(bytes);
                std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = bytes }) catch |err| try out.writer.print("error: {s}\n", .{@errorName(err)});
            },
        }
        try std.Io.File.stdout().writeStreamingAll(init.io, out.written());
    }
}

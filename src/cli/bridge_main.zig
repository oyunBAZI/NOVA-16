//! Versioned, bounded JSON-lines adapter. No protocol operation accepts a path.
const std = @import("std");
const n = @import("nova16");
const max_line = n.snapshot.v2_file_size * 2 + 4096;
pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        std.debug.print("n16bridge: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
fn run(init: std.process.Init) !void {
    const startup = init.arena.allocator();
    const args = try init.minimal.args.toSlice(startup);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--version")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, n.version ++ "\n");
        return;
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "n16bridge ROM [--symbols MAP]\nJSON lines protocol v1; see docs/workbench.md\n");
        return;
    }
    if (args.len != 2 and args.len != 4) return error.Usage_n16bridge_ROM_symbols_MAP;
    var m: n.Machine = .{};
    try m.load(try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], startup, .limited(8225)));
    const text = if (args.len == 4) blk: {
        if (!std.mem.eql(u8, args[2], "--symbols")) return error.BadArguments;
        break :blk try std.Io.Dir.cwd().readFileAlloc(init.io, args[3], startup, .limited(1024 * 1024));
    } else "";
    const symbols = try n.symbol_map.load(startup, text, m.checksum);
    defer symbols.deinit();
    var d: n.Debugger = .{ .machine = &m, .symbols = symbols.symbols, .sources = symbols.locations, .variables = symbols.variables };
    defer d.deinit();
    try d.recorder.configureDelta(2048);
    var session: n.workbench.Session = .{ .debugger = &d };
    // Reused bounded input allocation; all parsed/request/output allocations have
    // a per-request lifetime instead of accumulating in process.Init's arena.
    const allocator = std.heap.page_allocator;
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(allocator);
    var input_buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    while (true) {
        line.clearRetainingCapacity();
        var overflow = false;
        while (true) {
            const byte = input.interface.takeByte() catch |err| switch (err) {
                error.EndOfStream => {
                    if (line.items.len == 0 and !overflow) return;
                    break;
                },
                else => return err,
            };
            if (byte == '\n') break;
            if (line.items.len < max_line) try line.append(allocator, byte) else overflow = true;
        }
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var response: std.Io.Writer.Allocating = .init(a);
        if (overflow) {
            try response.writer.writeAll("{\"version\":1,\"ok\":false,\"error\":\"RequestTooLarge\"}\n");
        } else {
            try n.workbench_protocol.process(a, &session, line.items, &response.writer);
        }
        try std.Io.File.stdout().writeStreamingAll(init.io, response.written());
    }
}

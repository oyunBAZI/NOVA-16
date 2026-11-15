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
    try d.recorder.configure(32);
    var session: n.workbench.Session = .{ .debugger = &d };
    // Reused bounded input allocation; all parsed/request/output allocations have
    // a per-request lifetime instead of accumulating in process.Init's arena.
    const allocator = std.heap.page_allocator;
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(allocator);
    while (true) {
        line.clearRetainingCapacity();
        var overflow = false;
        while (true) {
            var byte: [1]u8 = undefined;
            const got = std.Io.File.stdin().readStreaming(init.io, &.{&byte}) catch |err| switch (err) {
                error.EndOfStream => 0,
                else => return err,
            };
            if (got == 0) {
                if (line.items.len == 0 and !overflow) return;
                break;
            }
            if (byte[0] == '\n') break;
            if (line.items.len < max_line) try line.append(allocator, byte[0]) else overflow = true;
        }
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var response: std.Io.Writer.Allocating = .init(a);
        if (overflow) {
            try response.writer.writeAll("{\"version\":1,\"ok\":false,\"error\":\"RequestTooLarge\"}\n");
        } else {
            const request = std.json.parseFromSlice(n.workbench.Request, a, line.items, .{ .allocate = .alloc_always }) catch {
                try std.Io.File.stdout().writeStreamingAll(init.io, "{\"version\":1,\"ok\":false,\"error\":\"BadRequest\"}\n");
                continue;
            };
            var output: std.Io.Writer.Allocating = .init(a);
            var failure: ?[]const u8 = null;
            const saved = session.apply(a, request.value, &output.writer) catch |err| blk: {
                failure = @errorName(err);
                break :blk null;
            };
            try response.writer.writeAll("{\"version\":1,\"ok\":");
            try std.json.Stringify.value(failure == null, .{}, &response.writer);
            try response.writer.writeAll(",\"error\":");
            try std.json.Stringify.value(failure, .{}, &response.writer);
            try response.writer.writeAll(",\"output\":");
            try std.json.Stringify.value(output.written(), .{}, &response.writer);
            if (saved) |bytes| {
                try response.writer.writeAll(",\"snapshot\":\"");
                try n.workbench.writeHex(&response.writer, bytes);
                try response.writer.writeByte('"');
            }
            // Invalid address windows do not make error reporting fail.
            var view = request.value;
            if (view.length > 256 or @as(u32, view.address) + view.length > 65536) view = .{};
            try session.writeObservation(a, &response.writer, view);
            try response.writer.writeAll("}\n");
        }
        try std.Io.File.stdout().writeStreamingAll(init.io, response.written());
    }
}

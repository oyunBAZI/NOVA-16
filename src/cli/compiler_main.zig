const std = @import("std");
const n = @import("nova16");
pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        if (err != error.Reported) std.debug.print("n16c: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
fn run(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--version")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, n.version ++ "\n");
        return;
    }
    if (args.len < 2) return error.Usage_n16c_SOURCE_out_ROM;
    if (std.mem.eql(u8, args[1], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "n16c SOURCE --out ROM [--assembly PATH] [--debug-symbols PATH] [--layout PATH] [--diagnostics text|json]\n");
        return;
    }
    var out: ?[]const u8 = null;
    var assembly: ?[]const u8 = null;
    var map: ?[]const u8 = null;
    var layout: ?[]const u8 = null;
    var json = false;
    var seen = std.StringHashMap(void).init(a);
    var i: usize = 2;
    while (i < args.len) : (i += 2) {
        if (i + 1 >= args.len) return error.MissingOptionValue;
        const key = args[i];
        if (seen.contains(key)) return error.DuplicateOption;
        try seen.put(key, {});
        const value = args[i + 1];
        if (std.mem.eql(u8, key, "--out")) out = value else if (std.mem.eql(u8, key, "--assembly")) assembly = value else if (std.mem.eql(u8, key, "--debug-symbols")) map = value else if (std.mem.eql(u8, key, "--layout")) layout = value else if (std.mem.eql(u8, key, "--diagnostics")) {
            if (std.mem.eql(u8, value, "json")) json = true else if (!std.mem.eql(u8, value, "text")) return error.InvalidDiagnosticFormat;
        } else return error.UnknownOption;
    }
    if (out == null) return error.MissingOutput;
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .limited(1024 * 1024));
    var diag: n.compiler.Diagnostic = .{};
    const result = n.compiler.compile(a, source, &diag) catch |err| {
        var text: std.Io.Writer.Allocating = .init(a);
        if (json) try std.json.Stringify.value(.{ .schema_version = @as(u16, 1), .file = args[1], .code = @errorName(err), .message = diag.reason, .line = diag.line, .column = diag.column, .offset = diag.offset, .length = diag.length, .token = diag.token }, .{}, &text.writer) else try text.writer.print("{s}:{d}:{d}: {s}: {s}", .{ args[1], diag.line, diag.column, @errorName(err), diag.token });
        try text.writer.writeByte('\n');
        try std.Io.File.stderr().writeStreamingAll(init.io, text.written());
        return error.Reported;
    };
    defer result.deinit();
    const outputs = @import("outputs.zig");
    var files: std.ArrayList(outputs.Artifact) = .empty;
    try files.append(a, .{ .path = out.?, .bytes = result.program.image });
    if (assembly) |path| try files.append(a, .{ .path = path, .bytes = result.assembly });
    if (map) |path| {
        var text: std.Io.Writer.Allocating = .init(a);
        try n.symbol_map.write(&text.writer, a, result.program, std.fs.path.basename(args[1]));
        try files.append(a, .{ .path = path, .bytes = try text.toOwnedSlice() });
    }
    if (layout) |path| {
        var text: std.Io.Writer.Allocating = .init(a);
        try std.json.Stringify.value(.{ .schema_version = @as(u16, 1), .abi_version = @as(u16, 1), .static_base = @as(u16, 0x100), .static_end = result.context.static_end, .frame_bytes = @as(u16, 256), .maximum_frames = @as(u16, 64), .rom_payload_bytes = result.program.image.len - 32 }, .{}, &text.writer);
        try files.append(a, .{ .path = path, .bytes = try text.toOwnedSlice() });
    }
    try outputs.publish(a, init.io, &.{args[1]}, files.items);
}

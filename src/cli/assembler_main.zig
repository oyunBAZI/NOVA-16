const std = @import("std");
const n = @import("nova16");
pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        if (err != error.DiagnosticReported) std.debug.print("n16asm: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
fn run(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len < 2) return error.Usage_n16asm_SOURCE_out_PATH;
    if (std.mem.eql(u8, args[1], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "n16asm SOURCE --out PATH [--symbols LEGACY_MAP] [--debug-symbols JSON_MAP]\n  [--listing PATH] [--diagnostics text|json]\n");
        return;
    }
    var out: ?[]const u8 = null;
    var sym: ?[]const u8 = null;
    var debug: ?[]const u8 = null;
    var listing: ?[]const u8 = null;
    var json = false;
    var seen = std.StringHashMap(void).init(a);
    defer seen.deinit();
    var k: usize = 2;
    while (k < args.len) : (k += 2) {
        if (k + 1 >= args.len) return error.MissingOptionValue;
        const opt = args[k];
        const value = args[k + 1];
        if (seen.contains(opt)) return error.DuplicateOption;
        try seen.put(opt, {});
        if (std.mem.eql(u8, opt, "--out")) out = value else if (std.mem.eql(u8, opt, "--symbols")) sym = value else if (std.mem.eql(u8, opt, "--debug-symbols")) debug = value else if (std.mem.eql(u8, opt, "--listing")) listing = value else if (std.mem.eql(u8, opt, "--diagnostics")) {
            if (std.mem.eql(u8, value, "json")) json = true else if (!std.mem.eql(u8, value, "text")) return error.InvalidDiagnosticFormat;
        } else return error.UnknownOption;
    }
    if (out == null) return error.MissingOutput;
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .limited(1024 * 1024));
    var d: n.assembler.Diagnostic = .{};
    const result = n.assembler.assemble(a, source, &d) catch {
        var error_text: std.Io.Writer.Allocating = .init(a);
        defer error_text.deinit();
        if (json) {
            try std.json.Stringify.value(.{ .schema_version = @as(u16, 1), .file = args[1], .code = d.code, .message = d.reason, .line = d.line, .column = d.column, .offset = d.offset, .length = d.length, .token = d.token }, .{}, &error_text.writer);
            try error_text.writer.writeByte('\n');
        } else try error_text.writer.print("{s}:{d}:{d}: {s}: {s}: {s}\n", .{ args[1], d.line, d.column, d.code, d.reason, d.token });
        try std.Io.File.stderr().writeStreamingAll(init.io, error_text.written());
        return error.DiagnosticReported;
    };
    defer result.deinit();
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out.?, .data = result.image });
    if (sym) |path| {
        var text: std.Io.Writer.Allocating = .init(a);
        defer text.deinit();
        for (result.symbols) |s| try text.writer.print("{x:0>4} {s}\n", .{ s.value, s.name });
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = text.written() });
    }
    if (debug) |path| {
        var text: std.Io.Writer.Allocating = .init(a);
        defer text.deinit();
        try n.symbol_map.write(&text.writer, a, result, args[1]);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = text.written() });
    }
    if (listing) |path| {
        var text: std.Io.Writer.Allocating = .init(a);
        defer text.deinit();
        try n.assembler.writeListing(&text.writer, result);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = text.written() });
    }
}

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
    if (args.len == 2 and std.mem.eql(u8, args[1], "--version")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, n.version ++ "\n");
        return;
    }
    if (args.len < 2) return error.Usage_n16asm_SOURCE_out_PATH;
    if (std.mem.eql(u8, args[1], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "n16asm SOURCE --out PATH [--symbols LEGACY_MAP] [--debug-symbols JSON_MAP]\n  [--architecture nova16-v1|nova16-v2] [--listing PATH] [--project-root DIR] [--diagnostics text|json|rich|json2]\n");
        return;
    }
    var profile: n.isa.Profile = .v1;
    var project_root: ?[]const u8 = null;
    var out: ?[]const u8 = null;
    var sym: ?[]const u8 = null;
    var debug: ?[]const u8 = null;
    var listing: ?[]const u8 = null;
    var json = false;
    var rich = false;
    var json2 = false;
    var seen = std.StringHashMap(void).init(a);
    defer seen.deinit();
    var k: usize = 2;
    while (k < args.len) : (k += 2) {
        if (k + 1 >= args.len) return error.MissingOptionValue;
        const opt = args[k];
        const value = args[k + 1];
        if (seen.contains(opt)) return error.DuplicateOption;
        try seen.put(opt, {});
        if (std.mem.eql(u8, opt, "--architecture")) profile = try n.isa.Profile.parse(value) else if (std.mem.eql(u8, opt, "--project-root")) project_root = value else if (std.mem.eql(u8, opt, "--out")) out = value else if (std.mem.eql(u8, opt, "--symbols")) sym = value else if (std.mem.eql(u8, opt, "--debug-symbols")) debug = value else if (std.mem.eql(u8, opt, "--listing")) listing = value else if (std.mem.eql(u8, opt, "--diagnostics")) {
            if (std.mem.eql(u8, value, "json")) json = true else if (std.mem.eql(u8, value, "json2")) json2 = true else if (std.mem.eql(u8, value, "rich")) rich = true else if (!std.mem.eql(u8, value, "text")) return error.InvalidDiagnosticFormat;
        } else return error.UnknownOption;
    }
    if (out == null) return error.MissingOutput;
    const expanded = try n.project.load(a, init.io, project_root orelse std.fs.path.dirname(args[1]) orelse ".", args[1]);
    defer expanded.deinit();
    const source = expanded.source;
    var d: n.assembler.Diagnostic = .{};
    const result = n.assembler.assembleProfile(a, source, &d, profile) catch {
        const first_origin = expanded.lines[@min(d.line - 1, expanded.lines.len - 1)];
        const diagnostic_file = if (expanded.files.len == 1) args[1] else first_origin.file;
        d.line = first_origin.line;
        d.offset = first_origin.offset + d.offset - first_origin.expanded_offset;
        var error_text: std.Io.Writer.Allocating = .init(a);
        defer error_text.deinit();
        if (rich or json2) {
            const errors = try n.assembler.diagnoseProfile(a, source, profile);
            if (json2) try error_text.writer.writeAll("{\"schema_version\":2,\"diagnostics\":[");
            for (errors.items[0..errors.len], 0..) |raw, index| {
                var item = raw;
                const origin = expanded.lines[@min(item.line - 1, expanded.lines.len - 1)];
                item.line = origin.line;
                const filename = if (expanded.files.len == 1) args[1] else origin.file;
                const reported_offset = origin.offset + item.offset - origin.expanded_offset;
                var start = item.offset;
                while (start > 0 and source[start - 1] != '\n') start -= 1;
                var end = item.offset;
                while (end < source.len and source[end] != '\n') end += 1;
                if (end > start and source[end - 1] == '\r') end -= 1;
                const suggestion: ?[]const u8 = if (std.mem.eql(u8, item.code, "ExpectedRegister")) "Use R0 through R7" else null;
                if (json2) {
                    if (index > 0) try error_text.writer.writeByte(',');
                    try std.json.Stringify.value(.{ .category = "assembly", .file = filename, .code = item.code, .message = item.reason, .line = item.line, .column = item.column, .offset = reported_offset, .length = item.length, .excerpt = source[start..end], .suggestion = suggestion }, .{}, &error_text.writer);
                } else {
                    try error_text.writer.print("{s}:{d}:{d}: {s}: {s}\n{s}\n", .{ filename, item.line, item.column, item.code, item.reason, source[start..end] });
                    for (source[start..][0 .. item.column - 1]) |c| try error_text.writer.writeByte(if (c == '\t') '\t' else ' ');
                    for (0..@min(@max(item.length, 1), 120)) |_| try error_text.writer.writeByte('^');
                    try error_text.writer.writeByte('\n');
                    if (suggestion) |hint| try error_text.writer.print("help: {s}\n", .{hint});
                }
            }
            if (json2) try error_text.writer.writeAll("]}\n");
        } else if (json) {
            try std.json.Stringify.value(.{ .schema_version = @as(u16, 1), .file = diagnostic_file, .code = d.code, .message = d.reason, .line = d.line, .column = d.column, .offset = d.offset, .length = d.length, .token = d.token }, .{}, &error_text.writer);
            try error_text.writer.writeByte('\n');
        } else try error_text.writer.print("{s}:{d}:{d}: {s}: {s}: {s}\n", .{ diagnostic_file, d.line, d.column, d.code, d.reason, d.token });
        try std.Io.File.stderr().writeStreamingAll(init.io, error_text.written());
        return error.DiagnosticReported;
    };
    defer result.deinit();
    for (result.locations) |*loc| {
        const origin = expanded.lines[loc.line - 1];
        loc.file = origin.file;
        loc.line = origin.line;
    }
    const outputs = @import("outputs.zig");
    var artifacts: std.ArrayList(outputs.Artifact) = .empty;
    defer artifacts.deinit(a);
    try artifacts.append(a, .{ .path = out.?, .bytes = result.image });
    if (sym) |path| {
        var text: std.Io.Writer.Allocating = .init(a);
        for (result.symbols) |s| try text.writer.print("{x:0>4} {s}\n", .{ s.value, s.name });
        try artifacts.append(a, .{ .path = path, .bytes = try text.toOwnedSlice() });
    }
    if (debug) |path| {
        var text: std.Io.Writer.Allocating = .init(a);
        try n.symbol_map.write(&text.writer, a, result, args[1]);
        try artifacts.append(a, .{ .path = path, .bytes = try text.toOwnedSlice() });
    }
    if (listing) |path| {
        var text: std.Io.Writer.Allocating = .init(a);
        try n.assembler.writeListing(&text.writer, result);
        try artifacts.append(a, .{ .path = path, .bytes = try text.toOwnedSlice() });
    }
    var inputs: std.ArrayList([]const u8) = .empty;
    defer inputs.deinit(a);
    for (expanded.files) |file| try inputs.append(a, try std.fs.path.join(a, &.{ expanded.root, file }));
    try outputs.publish(a, init.io, inputs.items, artifacts.items);
}

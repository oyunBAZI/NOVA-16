const std = @import("std");
const n = @import("nova16");
pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        std.debug.print("n16asm: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
fn run(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len < 2) return error.Usage_n16asm_SOURCE_out_PATH_symbols_PATH;
    if (std.mem.eql(u8, args[1], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "n16asm SOURCE --out PATH [--symbols PATH]\n");
        return;
    }
    var out: ?[]const u8 = null;
    var sym: ?[]const u8 = null;
    var k: usize = 2;
    while (k < args.len) : (k += 2) {
        if (k + 1 >= args.len) return error.MissingOptionValue;
        if (std.mem.eql(u8, args[k], "--out") and out == null) out = args[k + 1] else if (std.mem.eql(u8, args[k], "--symbols") and sym == null) sym = args[k + 1] else return error.UnknownOrDuplicateOption;
    }
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .limited(1024 * 1024));
    var d: n.assembler.Diagnostic = .{};
    const result = n.assembler.assemble(a, source, &d) catch |err| {
        std.debug.print("{s}:{d}:{d}: {s}: {s}\n", .{ args[1], d.line, d.column, d.reason, d.token });
        return err;
    };
    defer result.deinit();
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out orelse return error.MissingOutput, .data = result.image });
    if (sym) |path| {
        var text: std.Io.Writer.Allocating = .init(a);
        defer text.deinit();
        for (result.symbols) |s| try text.writer.print("{x:0>4} {s}\n", .{ s.value, s.name });
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = text.written() });
    }
}

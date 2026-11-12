const std = @import("std");
const asm16 = @import("../asm/assembler.zig");
pub const Source = struct { address: u32, length: usize, line: usize, column: usize, file: []const u8 };
pub const Variable = struct { name: []const u8, type_name: []const u8, address: u16, words: u16, frame_relative: bool = false, signed: bool = false, constant: ?u16 = null, scope_start: u32 = 0, scope_end: u32 = 65536 };
pub const Map = struct { schema_version: u16 = 2, rom_checksum: u32, symbols: []const asm16.Symbol, locations: []const Source, variables: []const Variable = &.{} };
pub fn write(w: *std.Io.Writer, a: std.mem.Allocator, result: asm16.Result, file: []const u8) !void {
    const locations = try a.alloc(Source, result.locations.len);
    defer a.free(locations);
    for (result.locations, locations) |s, *d| d.* = .{ .address = s.address, .length = s.length, .line = s.line, .column = s.column, .file = if (s.file.len > 0) s.file else file };
    const map = .{ .schema_version = @as(u16, 2), .rom_checksum = std.mem.readInt(u32, result.image[12..16], .little), .symbols = result.symbols, .locations = locations };
    try std.json.Stringify.value(map, .{}, w);
    try w.writeByte('\n');
}
pub const Loaded = struct {
    symbols: []const asm16.Symbol,
    locations: []const Source = &.{},
    variables: []const Variable = &.{},
    parsed: ?std.json.Parsed(Map) = null,
    legacy: ?[]asm16.Symbol = null,
    allocator: std.mem.Allocator,
    pub fn deinit(self: Loaded) void {
        if (self.parsed) |p| p.deinit();
        if (self.legacy) |s| self.allocator.free(s);
    }
};
pub fn load(a: std.mem.Allocator, text: []const u8, checksum: u32) !Loaded {
    if (text.len > 1024 * 1024) return error.SymbolMapTooLarge;
    const trimmed = std.mem.trim(u8, text, " \r\n\t");
    if (std.mem.startsWith(u8, trimmed, "{")) {
        const parsed = try std.json.parseFromSlice(Map, a, trimmed, .{ .allocate = .alloc_always });
        errdefer parsed.deinit();
        if (parsed.value.schema_version != 2 and parsed.value.schema_version != 3) return error.UnsupportedSymbolSchema;
        if (parsed.value.schema_version == 2 and parsed.value.variables.len != 0) return error.InvalidSourceMap;
        if (parsed.value.variables.len > 1024) return error.InvalidSourceMap;
        for (parsed.value.variables) |variable| {
            const end = @as(u32, variable.address) + @as(u32, variable.words) * 2;
            if (variable.name.len == 0 or variable.words == 0 or variable.address & 1 != 0 or variable.scope_start >= variable.scope_end or variable.scope_end > 65536) return error.InvalidSourceMap;
            if (variable.frame_relative) {
                if (end > 256) return error.InvalidSourceMap;
            } else if (end > 0x4000) return error.InvalidSourceMap;
        }
        if (parsed.value.rom_checksum != checksum) return error.SymbolRomMismatch;
        for (parsed.value.locations) |loc| if (loc.address < 0xe000 or loc.address > 65535 or loc.length > 65536 - loc.address or loc.line == 0 or loc.column == 0) return error.InvalidSourceMap;
        return .{ .symbols = parsed.value.symbols, .locations = parsed.value.locations, .variables = parsed.value.variables, .parsed = parsed, .allocator = a };
    }
    var items: std.ArrayList(asm16.Symbol) = .empty;
    errdefer items.deinit(a);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var words = std.mem.tokenizeAny(u8, line, " \t\r");
        const address = words.next() orelse continue;
        const name = words.next() orelse return error.BadSymbolMap;
        if (words.next() != null) return error.BadSymbolMap;
        try items.append(a, .{ .name = name, .value = try std.fmt.parseInt(i64, address, 16) });
    }
    const legacy = try items.toOwnedSlice(a);
    return .{ .symbols = legacy, .legacy = legacy, .allocator = a };
}
test "versioned symbols associate source spans and reject wrong ROM; legacy remains readable" {
    const a = std.testing.allocator;
    var d: asm16.Diagnostic = .{};
    const r = try asm16.assemble(a, "start: HALT", &d);
    defer r.deinit();
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    try write(&out.writer, a, r, "test.asm");
    const crc = std.mem.readInt(u32, r.image[12..16], .little);
    const loaded = try load(a, out.written(), crc);
    defer loaded.deinit();
    try std.testing.expectEqual(1, loaded.locations.len);
    try std.testing.expectError(error.SymbolRomMismatch, load(a, out.written(), crc +% 1));
    const old = try load(a, "e000 start\n", crc);
    defer old.deinit();
    try std.testing.expectEqualStrings("start", old.symbols[0].name);
}

test "compiler map variables are versioned and range checked" {
    const a = std.testing.allocator;
    const good = "{\"schema_version\":3,\"rom_checksum\":17,\"symbols\":[],\"locations\":[],\"variables\":[{\"name\":\"x\",\"type_name\":\"u16\",\"address\":254,\"words\":1,\"frame_relative\":true}]}";
    const valid = try load(a, good, 17);
    defer valid.deinit();
    try std.testing.expectEqual(1, valid.variables.len);
    for ([_][]const u8{ "{\"schema_version\":2,\"rom_checksum\":17,\"symbols\":[],\"locations\":[],\"variables\":[{\"name\":\"x\",\"type_name\":\"u16\",\"address\":0,\"words\":1}]}", "{\"schema_version\":3,\"rom_checksum\":17,\"symbols\":[],\"locations\":[],\"variables\":[{\"name\":\"x\",\"type_name\":\"u16\",\"address\":256,\"words\":1,\"frame_relative\":true}]}" }) |bad| try std.testing.expectError(error.InvalidSourceMap, load(a, bad, 17));
}

//! Explicit Wasm embedding ABI, no imports, host I/O, clocks, entropy or callbacks.
const std = @import("std");
const n = @import("nova16");
const allocator = std.heap.wasm_allocator;
var input: [1024 * 1024]u8 = undefined;
var output: [512000]u8 = undefined;
var output_length: usize = 0;
var machine: n.Machine = .{};
var debugger: n.Debugger = .{ .machine = &machine, .recorder = .{ .allocator = allocator } };
var session: n.workbench.Session = .{ .debugger = &debugger };
var loaded: bool = false;
var symbols: ?n.symbol_map.Loaded = null;
var symbol_text: ?[]u8 = null;
export fn n16_version_ptr() usize {
    return @intFromPtr(n.version.ptr);
}
export fn n16_version_length() usize {
    return n.version.len;
}
export fn n16_abi_version() u32 {
    return 1;
}
export fn n16_input_ptr() usize {
    return @intFromPtr(&input);
}
export fn n16_input_capacity() usize {
    return input.len;
}
export fn n16_output_ptr() usize {
    return @intFromPtr(&output);
}
export fn n16_output_length() usize {
    return output_length;
}
fn failure(err: anyerror) u32 {
    var writer = std.Io.Writer.fixed(&output);
    writer.print("{{\"version\":1,\"ok\":false,\"error\":\"{s}\"}}", .{@errorName(err)}) catch unreachable;
    output_length = writer.end;
    return 0;
}
fn prepareHistory() !void {
    if (debugger.recorder.capacity() == 0) try debugger.recorder.configureDelta(256);
}
fn clearSymbols() void {
    if (symbols) |old| old.deinit();
    if (symbol_text) |text| allocator.free(text);
    symbol_text = null;
    symbols = null;
    debugger.symbols = &.{};
    debugger.sources = &.{};
    debugger.variables = &.{};
}
fn installSymbols(fresh: n.symbol_map.Loaded, owned_text: ?[]u8) void {
    clearSymbols();
    symbols = fresh;
    symbol_text = owned_text;
    debugger.symbols = fresh.symbols;
    debugger.sources = fresh.locations;
    debugger.variables = fresh.variables;
}
fn replace(data: []const u8) !void {
    _ = try n.rom.parse(data);
    try prepareHistory();
    try machine.load(data);
    clearSymbols();
    debugger.clearHistory();
    debugger.breaks = @splat(false);
    debugger.watches = @splat(false);
    session.pcm_valid = false;
    session.stopped = true;
    loaded = true;
}
fn observe() u32 {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var writer = std.Io.Writer.fixed(&output);
    n.workbench_protocol.process(arena.allocator(), &session, "{}", &writer) catch |err| return failure(err);
    output_length = writer.end;
    return 1;
}
export fn n16_load(length: usize) u32 {
    if (length > 8224) return failure(error.RomTooLarge);
    replace(input[0..length]) catch |err| return failure(err);
    return observe();
}
export fn n16_request(length: usize) u32 {
    if (!loaded) return failure(error.NoRomLoaded);
    if (length > input.len) return failure(error.RequestTooLarge);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var writer = std.Io.Writer.fixed(&output);
    n.workbench_protocol.process(arena.allocator(), &session, input[0..length], &writer) catch |err| return failure(err);
    output_length = writer.end;
    return 1;
}
export fn n16_set_symbols(length: usize) u32 {
    if (!loaded) return failure(error.NoRomLoaded);
    if (length > input.len) return failure(error.SymbolMapTooLarge);
    const text = allocator.dupe(u8, input[0..length]) catch |err| return failure(err);
    const fresh = n.symbol_map.load(allocator, text, machine.checksum) catch |err| {
        allocator.free(text);
        return failure(err);
    };
    if (fresh.legacy != null) installSymbols(fresh, text) else {
        allocator.free(text);
        installSymbols(fresh, null);
    }
    return observe();
}
export fn n16_compile(length: usize, profile: u32, optimization: u32) u32 {
    if (length > 65536) return failure(error.SourceTooLarge);
    if (profile != 1 and profile != 2) return failure(error.InvalidArchitecture);
    if (optimization > 1) return failure(error.InvalidOptimization);
    var diagnostic: n.compiler.Diagnostic = .{};
    const result = n.compiler.compileWithOptions(allocator, input[0..length], &diagnostic, .{ .profile = if (profile == 1) .v1 else .v2, .optimization = if (optimization == 0) .none else .size }) catch |err| {
        var writer = std.Io.Writer.fixed(&output);
        std.json.Stringify.value(.{ .version = @as(u16, 1), .ok = false, .@"error" = @errorName(err), .line = diagnostic.line, .column = diagnostic.column, .token = diagnostic.token }, .{}, &writer) catch return failure(error.OutputLimit);
        output_length = writer.end;
        return 0;
    };
    defer result.deinit();
    var map: std.Io.Writer.Allocating = .init(allocator);
    defer map.deinit();
    n.compiler.writeDebugMap(&map.writer, allocator, result, "main.n16c") catch |err| return failure(err);
    const fresh = n.symbol_map.load(allocator, map.written(), std.mem.readInt(u32, result.program.image[12..16], .little)) catch |err| return failure(err);
    replace(result.program.image) catch |err| {
        fresh.deinit();
        return failure(err);
    };
    installSymbols(fresh, null);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var writer = std.Io.Writer.fixed(&output);
    writer.writeAll("{\"version\":1,\"ok\":true,\"rom\":\"") catch return failure(error.OutputLimit);
    n.workbench.writeHex(&writer, result.program.image) catch return failure(error.OutputLimit);
    writer.writeAll("\",\"size_report\":") catch return failure(error.OutputLimit);
    n.compiler.writeSizeReport(&writer, arena.allocator(), result) catch |err| return failure(err);
    session.writeObservation(arena.allocator(), &writer, .{}) catch |err| return failure(err);
    writer.writeByte('}') catch return failure(error.OutputLimit);
    output_length = writer.end;
    return 1;
}
export fn n16_dispose() void {
    clearSymbols();
    debugger.deinit();
    machine = .{};
    debugger = .{ .machine = &machine, .recorder = .{ .allocator = allocator } };
    session = .{ .debugger = &debugger };
    loaded = false;
    output_length = 0;
}

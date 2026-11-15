//! Shared bounded request/response serialization for native and Wasm hosts.
const std = @import("std");
const workbench = @import("session.zig");
pub const maximum_response_bytes = 500000;
pub fn process(a: std.mem.Allocator, session: *workbench.Session, line: []const u8, response: *std.Io.Writer) !void {
    // A valid but very large map/inspection must never exceed a host reader's
    // framing limit or terminate the live VM. Serialize before publication.
    const storage = try a.alloc(u8, maximum_response_bytes);
    defer a.free(storage);
    var bounded = std.Io.Writer.fixed(storage);
    processInto(a, session, line, &bounded) catch |err| {
        if (err != error.WriteFailed) return err;
        try response.writeAll("{\"version\":1,\"ok\":false,\"error\":\"OutputLimit\"}\n");
        return;
    };
    try response.writeAll(bounded.buffered());
}
fn processInto(a: std.mem.Allocator, session: *workbench.Session, line: []const u8, response: *std.Io.Writer) !void {
    if (line.len > @import("../core/snapshot.zig").v2_file_size * 2 + 4096) {
        try response.writeAll("{\"version\":1,\"ok\":false,\"error\":\"RequestTooLarge\"}\n");
        return;
    }
    const request = std.json.parseFromSlice(workbench.Request, a, line, .{ .allocate = .alloc_always }) catch {
        try response.writeAll("{\"version\":1,\"ok\":false,\"error\":\"BadRequest\"}\n");
        return;
    };
    defer request.deinit();
    const command_storage = try a.alloc(u8, 65536);
    defer a.free(command_storage);
    var output = std.Io.Writer.fixed(command_storage);
    var failure: ?[]const u8 = null;
    const saved = session.apply(a, request.value, &output) catch |err| blk: {
        failure = if (err == error.WriteFailed) "OutputLimit" else @errorName(err);
        break :blk null;
    };
    defer if (saved) |bytes| a.free(bytes);
    try response.writeAll("{\"version\":1,\"ok\":");
    try std.json.Stringify.value(failure == null, .{}, response);
    try response.writeAll(",\"error\":");
    try std.json.Stringify.value(failure, .{}, response);
    try response.writeAll(",\"output\":");
    try std.json.Stringify.value(if (failure != null and std.mem.eql(u8, failure.?, "OutputLimit")) @as([]const u8, "") else output.buffered(), .{}, response);
    if (saved) |bytes| {
        try response.writeAll(",\"snapshot\":\"");
        try workbench.writeHex(response, bytes);
        try response.writeByte('"');
    }
    var view = request.value;
    if (view.length > 256 or @as(u32, view.address) + view.length > 65536) view = .{};
    try session.writeObservation(a, response, view);
    try response.writeAll("}\n");
}

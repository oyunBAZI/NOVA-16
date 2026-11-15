//! Shared bounded request/response serialization for native and Wasm hosts.
const std = @import("std");
const workbench = @import("session.zig");
pub fn process(a: std.mem.Allocator, session: *workbench.Session, line: []const u8, response: *std.Io.Writer) !void {
    if (line.len > @import("../core/snapshot.zig").v2_file_size * 2 + 4096) {
        try response.writeAll("{\"version\":1,\"ok\":false,\"error\":\"RequestTooLarge\"}\n");
        return;
    }
    const request = std.json.parseFromSlice(workbench.Request, a, line, .{ .allocate = .alloc_always }) catch {
        try response.writeAll("{\"version\":1,\"ok\":false,\"error\":\"BadRequest\"}\n");
        return;
    };
    defer request.deinit();
    var output: std.Io.Writer.Allocating = .init(a);
    defer output.deinit();
    var failure: ?[]const u8 = null;
    const saved = session.apply(a, request.value, &output.writer) catch |err| blk: {
        failure = @errorName(err);
        break :blk null;
    };
    defer if (saved) |bytes| a.free(bytes);
    try response.writeAll("{\"version\":1,\"ok\":");
    try std.json.Stringify.value(failure == null, .{}, response);
    try response.writeAll(",\"error\":");
    try std.json.Stringify.value(failure, .{}, response);
    try response.writeAll(",\"output\":");
    try std.json.Stringify.value(output.written(), .{}, response);
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

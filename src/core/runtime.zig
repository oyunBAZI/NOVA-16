const std = @import("std");
pub const Event = struct { frame: u64, bits: u8 };
/// Each line is frame-number input-mask; masks persist until the next event.
pub fn parseSchedule(a: std.mem.Allocator, text: []const u8) ![]Event {
    var events: std.ArrayList(Event) = .empty;
    errdefer events.deinit(a);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var words = std.mem.tokenizeAny(u8, line, " \t");
        const frame = try std.fmt.parseInt(u64, words.next() orelse return error.BadSchedule, 0);
        const bits = try std.fmt.parseInt(u8, words.next() orelse return error.BadSchedule, 0);
        if (words.next() != null or (events.items.len > 0 and events.items[events.items.len - 1].frame >= frame)) return error.BadSchedule;
        try events.append(a, .{ .frame = frame, .bits = bits });
    }
    return events.toOwnedSlice(a);
}
test "ordered input schedule strict parsing" {
    const a = std.testing.allocator;
    const e = try parseSchedule(a, "# test\n0 0x10\n2 0\n");
    defer a.free(e);
    try std.testing.expectEqual(16, e[0].bits);
    try std.testing.expectError(error.BadSchedule, parseSchedule(a, "1 1\n1 2"));
}

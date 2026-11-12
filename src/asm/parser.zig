const lex = @import("lexer.zig");
const std = @import("std");
pub const Line = struct { label: ?[]const u8 = null, name: []const u8 = "", args: []const u8 = "" };
pub fn parse(source: []const u8) !Line {
    var s = lex.code(source);
    var line: Line = .{};
    if (s.len == 0) return line;
    // A colon in an ASCII string is data, not a label separator.
    const end = std.mem.indexOfAny(u8, s, " \t");
    if (std.mem.indexOfScalar(u8, s, ':')) |k| {
        if (end == null or k < end.?) {
            if (!lex.identifier(s[0..k])) return error.InvalidSymbol;
            line.label = s[0..k];
            s = lex.trim(s[k + 1 ..]);
        }
    }
    const k = std.mem.indexOfAny(u8, s, " \t") orelse s.len;
    line.name = s[0..k];
    line.args = lex.trim(s[k..]);
    return line;
}

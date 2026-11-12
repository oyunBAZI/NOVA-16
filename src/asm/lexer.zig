const std = @import("std");
pub fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r");
}
/// Strip comments only outside quoted strings.
pub fn code(line: []const u8) []const u8 {
    var quoted = false;
    var escape = false;
    for (line, 0..) |c, k| {
        if (escape) {
            escape = false;
            continue;
        }
        if (c == '\\' and quoted) {
            escape = true;
            continue;
        }
        if (c == '"') quoted = !quoted;
        if (c == ';' and !quoted) return trim(line[0..k]);
    }
    return trim(line);
}
pub fn identifier(s: []const u8) bool {
    if (s.len == 0 or !(std.ascii.isAlphabetic(s[0]) or s[0] == '_')) return false;
    for (s[1..]) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    return true;
}
pub const Parts = struct { items: [64][]const u8 = undefined, len: usize = 0 };
pub fn operands(s: []const u8) !Parts {
    var result: Parts = .{};
    var quote = false;
    var escape = false;
    var bracket: i32 = 0;
    var start: usize = 0;
    for (s, 0..) |c, k| {
        if (escape) {
            escape = false;
            continue;
        }
        if (c == '\\' and quote) {
            escape = true;
            continue;
        }
        if (c == '"') quote = !quote;
        if (quote) continue;
        if (c == '[') bracket += 1;
        if (c == ']') bracket -= 1;
        if (bracket < 0 or bracket > 1) return error.Syntax;
        if (c == ',' and bracket == 0) {
            if (result.len == 64) return error.TooManyOperands;
            result.items[result.len] = trim(s[start..k]);
            result.len += 1;
            start = k + 1;
        }
    }
    if (quote or bracket != 0) return error.Syntax;
    if (trim(s).len != 0) {
        if (result.len == 64) return error.TooManyOperands;
        result.items[result.len] = trim(s[start..]);
        result.len += 1;
    }
    for (result.items[0..result.len]) |v| if (v.len == 0) return error.Syntax;
    return result;
}

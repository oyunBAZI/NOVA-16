const std = @import("std");
pub const Token = struct { text: []const u8, line: usize = 1, column: usize = 1, kind: enum { name, number, punctuation, eof } };
pub fn lex(a: std.mem.Allocator, source: []const u8, diag: *@import("../asm/diagnostic.zig").Diagnostic) ![]Token {
    if (source.len > 1024 * 1024) return error.SourceTooLarge;
    if (!std.unicode.utf8ValidateSlice(source)) return error.InvalidUtf8;
    var tokens: std.ArrayList(Token) = .empty;
    var p: usize = 0;
    var line: usize = 1;
    var line_start: usize = 0;
    while (p < source.len) {
        const start = p;
        const token_line = line;
        const c = source[p];
        if (std.ascii.isWhitespace(c)) {
            if (c == '\n') {
                line += 1;
                line_start = p + 1;
            }
            p += 1;
            continue;
        }
        diag.* = .{ .token = source[p..][0..1], .offset = p, .length = 1, .line = line, .column = p - line_start + 1 };
        if (std.mem.startsWith(u8, source[p..], "//")) {
            while (p < source.len and source[p] != '\n') p += 1;
            continue;
        }
        if (std.mem.startsWith(u8, source[p..], "/*")) {
            const end = std.mem.indexOf(u8, source[p + 2 ..], "*/") orelse return error.UnterminatedComment;
            p += end + 4;
            line += std.mem.count(u8, source[start..p], "\n");
            if (std.mem.lastIndexOfScalar(u8, source[start..p], '\n')) |last| line_start = start + last + 1;
            continue;
        }
        var kind: @FieldType(Token, "kind") = .punctuation;
        if (std.ascii.isAlphabetic(c) or c == '_') {
            kind = .name;
            p += 1;
            while (p < source.len and (std.ascii.isAlphanumeric(source[p]) or source[p] == '_')) p += 1;
            if (p - start > 64) return error.IdentifierLimit;
        } else if (std.ascii.isDigit(c)) {
            kind = .number;
            p += 1;
            while (p < source.len and std.ascii.isAlphanumeric(source[p])) p += 1;
        } else {
            if (std.mem.indexOfScalar(u8, "+-*/%&|^<>!=~(){}[]:;,.?", c) == null) return error.InvalidCharacter;
            p += 1;
            if (p < source.len) for ([_][]const u8{ "->", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||" }) |op| {
                if (std.mem.startsWith(u8, source[start..], op)) {
                    p += 1;
                    break;
                }
            };
        }
        if (tokens.items.len == 32768) return error.TokenLimit;
        try tokens.append(a, .{ .text = source[start..p], .kind = kind, .line = token_line, .column = start - line_start + 1 });
    }
    try tokens.append(a, .{ .text = source[source.len..], .kind = .eof, .line = line, .column = source.len - line_start + 1 });
    return tokens.toOwnedSlice(a);
}

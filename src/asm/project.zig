//! Host-side local textual inclusion. No host I/O enters the virtual machine.
const std = @import("std");
const lex = @import("lexer.zig");
pub const Line = struct { file: []const u8, line: usize };
pub const Expanded = struct {
    allocator: std.mem.Allocator,
    source: []u8,
    lines: []Line,
    files: [][]const u8,
    pub fn deinit(self: Expanded) void {
        self.allocator.free(self.source);
        self.allocator.free(self.lines);
        for (self.files) |file| self.allocator.free(file);
        self.allocator.free(self.files);
    }
};
const Loader = struct {
    a: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    out: std.Io.Writer.Allocating,
    lines: std.ArrayList(Line) = .empty,
    files: std.ArrayList([]const u8) = .empty,
    stack: std.ArrayList([]const u8) = .empty,
    total: usize = 0,
    fn visit(self: *Loader, path: []const u8) anyerror!void {
        if (self.stack.items.len >= 32) return error.IncludeDepth;
        if (self.files.items.len >= 128) return error.IncludeFileLimit;
        const real = try std.Io.Dir.cwd().realPathFileAlloc(self.io, path, self.a);
        defer self.a.free(real);
        if (!inside(self.root, real)) return error.ProjectBoundary;
        for (self.stack.items) |parent| if (std.mem.eql(u8, real, parent)) return error.IncludeCycle;
        const text = try std.Io.Dir.cwd().readFileAlloc(self.io, real, self.a, .limited(1024 * 1024));
        defer self.a.free(text);
        if (text.len > 1024 * 1024 - self.total) return error.ProjectTooLarge;
        self.total += text.len;
        const relative = try self.a.dupe(u8, real[self.root.len + @as(usize, if (std.fs.path.isSep(self.root[self.root.len - 1])) 0 else 1) ..]);
        errdefer self.a.free(relative);
        for (relative) |*c| if (c.* == '\\') {
            c.* = '/';
        };
        try self.files.append(self.a, relative);
        try self.stack.append(self.a, real);
        defer _ = self.stack.pop();
        var lines = std.mem.splitScalar(u8, text, '\n');
        var number: usize = 0;
        while (lines.next()) |line| {
            number += 1;
            const code = lex.code(line);
            if (std.mem.startsWith(u8, code, ".include") and (code.len == 8 or code[8] == ' ' or code[8] == '\t')) {
                const name = lex.trim(code[8..]);
                if (name.len < 3 or name[0] != '"' or name[name.len - 1] != '"') return error.IncludeSyntax;
                const sub = name[1 .. name.len - 1];
                if (std.mem.indexOfAny(u8, sub, "\\:\x00\"") != null or std.fs.path.isAbsolute(sub)) return error.IncludePath;
                const child = try std.fs.path.join(self.a, &.{ std.fs.path.dirname(real).?, sub });
                defer self.a.free(child);
                try self.visit(child);
            } else {
                if (self.lines.items.len >= 32768 or self.out.written().len + line.len + 1 > 1024 * 1024) return error.ProjectTooLarge;
                try self.lines.append(self.a, .{ .file = relative, .line = number });
                try self.out.writer.writeAll(line);
                try self.out.writer.writeByte('\n');
            }
        }
    }
};
fn inside(root: []const u8, file: []const u8) bool {
    if (file.len <= root.len or !std.mem.startsWith(u8, file, root)) return false;
    return std.fs.path.isSep(root[root.len - 1]) or std.fs.path.isSep(file[root.len]);
}
pub fn load(a: std.mem.Allocator, io: std.Io, root: []const u8, entry: []const u8) !Expanded {
    const real = try std.Io.Dir.cwd().realPathFileAlloc(io, root, a);
    defer a.free(real);
    var loader: Loader = .{ .a = a, .io = io, .root = real, .out = .init(a) };
    defer loader.out.deinit();
    defer loader.stack.deinit(a);
    defer loader.lines.deinit(a);
    defer {
        for (loader.files.items) |file| a.free(file);
        loader.files.deinit(a);
    }
    try loader.visit(entry);
    const source = try loader.out.toOwnedSlice();
    errdefer a.free(source);
    const lines = try loader.lines.toOwnedSlice(a);
    errdefer a.free(lines);
    return .{ .allocator = a, .source = source, .lines = lines, .files = try loader.files.toOwnedSlice(a) };
}
test "project boundary matching requires a complete path component" {
    try std.testing.expect(inside("/a/b", "/a/b/main.asm"));
    try std.testing.expect(!inside("/a/b", "/a/bad/main.asm"));
    try std.testing.expect(!inside("/a/b", "/a/b"));
}

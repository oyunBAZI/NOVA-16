//! Stage every artifact before publishing; replace ROM last as commit marker.
//! No cross-file crash-atomicity is promised by ordinary host filesystems.
const std = @import("std");
pub const Artifact = struct { path: []const u8, bytes: []const u8 };
pub fn publish(a: std.mem.Allocator, io: std.Io, sources: []const []const u8, artifacts: []const Artifact) !void {
    const cwd = std.Io.Dir.cwd();
    var inputs: std.ArrayList([]const u8) = .empty;
    defer {
        for (inputs.items) |path| a.free(path);
        inputs.deinit(a);
    }
    for (sources) |source| {
        const path = try cwd.realPathFileAlloc(io, source, a);
        errdefer a.free(path);
        try inputs.append(a, path);
    }
    var normalized: std.ArrayList([]const u8) = .empty;
    defer {
        for (normalized.items) |p| a.free(p);
        normalized.deinit(a);
    }
    for (artifacts) |item| {
        if (item.path.len == 0) return error.InvalidOutputPath;
        // Resolve parent, including symlinks, before comparing aliases.
        const parent = try cwd.realPathFileAlloc(io, std.fs.path.dirname(item.path) orelse ".", a);
        defer a.free(parent);
        const path = try std.fs.path.join(a, &.{ parent, std.fs.path.basename(item.path) });
        errdefer a.free(path);
        for (inputs.items) |input| if (std.ascii.eqlIgnoreCase(input, path)) return error.OutputAliasesSource;
        for (normalized.items) |p| if (std.ascii.eqlIgnoreCase(p, path)) return error.DuplicateOutputPath;
        // Reject symlinks/non-files. Replacing a regular hardlink preserves its other names.
        if (cwd.statFile(io, item.path, .{ .follow_symlinks = false })) |stat| {
            if (stat.kind != .file) return error.InvalidOutputPath;
            const canonical = try cwd.realPathFileAlloc(io, item.path, a);
            defer a.free(canonical);
            for (inputs.items) |input| if (std.ascii.eqlIgnoreCase(canonical, input)) return error.OutputAliasesSource;
        } else |err| if (err != error.FileNotFound) return err;
        try normalized.append(a, path);
    }
    var staged: std.ArrayList(std.Io.File.Atomic) = .empty;
    defer {
        for (staged.items) |*file| file.deinit(io);
        staged.deinit(a);
    }
    for (artifacts) |item| {
        var file = try cwd.createFileAtomic(io, item.path, .{ .replace = true });
        errdefer file.deinit(io);
        try file.file.writeStreamingAll(io, item.bytes);
        try staged.append(a, file);
    }
    var k = staged.items.len;
    while (k > 0) {
        k -= 1;
        try staged.items[k].replace(io);
    }
}

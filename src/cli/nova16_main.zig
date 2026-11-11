const std = @import("std");
pub fn main(init: std.process.Init) !void {
    try std.Io.File.stdout().writeStreamingAll(init.io, "NOVA-16 virtual computer\n");
}

const std = @import("std");
pub fn main(init: std.process.Init) !void {
    try @import("nova16").sdl.selfTest(init.arena.allocator());
    try std.Io.File.stdout().writeStreamingAll(init.io, "SDL2 ABI/events/controls/scaling/readback passed\n");
}

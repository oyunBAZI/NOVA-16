const std = @import("std");
const Machine = @import("../core/machine.zig").Machine;
pub fn json(w: *std.Io.Writer, m: *const Machine) !void {
    const c = &m.cpu;
    try w.print("{{\"schema_version\":1,\"rom_checksum\":{d},\"executed_instructions\":{d},\"frame_count\":{d},\"registers\":[", .{ m.checksum, c.retired, m.bus.frame });
    for (c.r, 0..) |r, k| {
        if (k != 0) try w.writeByte(',');
        try w.print("{d}", .{r});
    }
    try w.print("],\"pc\":{d},\"sp\":{d},\"flags\":{d},\"halted\":{s},\"paused\":{s},\"trapped\":{s},\"trap\":", .{ c.pc, c.sp, c.flags, if (c.halted) "true" else "false", if (c.paused) "true" else "false", if (c.trap != null) "true" else "false" });
    if (c.trap) |t| try w.print("{{\"kind\":\"{s}\",\"pc\":{d},\"address\":{d},\"access\":\"{s}\"}}", .{ @errorName(t.kind), t.pc, t.address, @tagName(t.access) }) else try w.writeAll("null");
    try w.print(",\"vram_checksum\":{d}}}\n", .{std.hash.Crc32.hash(m.bus.bytes[0xc000..0xd800])});
}

const std = @import("std");
const Machine = @import("../core/machine.zig").Machine;
pub fn json(w: *std.Io.Writer, m: *const Machine) !void {
    const c = &m.cpu;
    try w.print("{{\"schema_version\":{d},\"rom_checksum\":{d},\"executed_instructions\":{d},\"frame_count\":{d},\"registers\":[", .{ @as(u8, if (m.bus.profile == .v2) 2 else 1), m.checksum, c.retired, m.bus.frame });
    for (c.r, 0..) |r, k| {
        if (k != 0) try w.writeByte(',');
        try w.print("{d}", .{r});
    }
    try w.print("],\"pc\":{d},\"sp\":{d},\"flags\":{d},\"halted\":{s},\"paused\":{s},\"trapped\":{s},\"trap\":", .{ c.pc, c.sp, c.flags, if (c.halted) "true" else "false", if (c.paused) "true" else "false", if (c.trap != null) "true" else "false" });
    if (c.trap) |t| try w.print("{{\"kind\":\"{s}\",\"pc\":{d},\"address\":{d},\"access\":\"{s}\"}}", .{ @errorName(t.kind), t.pc, t.address, @tagName(t.access) }) else try w.writeAll("null");
    if (m.bus.profile == .v2) {
        try w.print(",\"machine_profile\":2,\"transition_slots\":{d},\"irq_entries\":{d},\"audio_samples\":{d},\"pcm_prefix\":{d},\"irq_pending\":{d},\"irq_mask\":{d},\"irq_ie\":{s},\"irq_depth\":{d},\"timer_period\":{d},\"timer_remaining\":{d}", .{ m.slots, m.irq_entries, m.bus.audio.generated, m.bus.audio.prefix, m.bus.irq.pending, m.bus.irq.mask, if (m.bus.irq.ie) "true" else "false", m.bus.irq.depth, m.bus.irq.period, m.bus.irq.remaining });
    }
    try w.print(",\"vram_checksum\":{d}}}\n", .{std.hash.Crc32.hash(m.bus.bytes[0xc000..0xd800])});
}

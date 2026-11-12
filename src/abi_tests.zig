const std = @import("std");
const n = @import("root.zig");
test "ABI1 nested guest calls preserve registers frames returns and real stack" {
    var d: n.assembler.Diagnostic = .{};
    const r = try n.assembler.assemble(std.testing.allocator, @import("examples").abi, &d);
    defer r.deinit();
    var m: n.Machine = .{};
    try m.load(r.image);
    for (0..500) |_| {
        m.step();
        if (m.cpu.halted or m.cpu.trap != null) break;
    }
    try std.testing.expect(m.cpu.halted and m.cpu.trap == null);
    try std.testing.expectEqual(49, m.cpu.r[0]);
    try std.testing.expectEqualSlices(u16, &.{ 0x4444, 0x5555, 0x6666, 0x8000 }, m.cpu.r[4..]);
    try std.testing.expectEqual(0xbffe, m.cpu.sp);
    try std.testing.expectEqual(0, m.cpu.depth);
    try std.testing.expectEqual(49, try m.bus.read16(0x100));
    try std.testing.expectEqual(19, try m.bus.read16(0x7f00));
    try std.testing.expectEqual(23, try m.bus.read16(0x7f02));
    try std.testing.expectEqual(7, try m.bus.read16(0x7e00));
}

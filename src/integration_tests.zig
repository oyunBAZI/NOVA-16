const std = @import("std");
const asm16 = @import("asm/assembler.zig");
const Machine = @import("core/machine.zig").Machine;
const video = @import("devices/video.zig");
const examples = @import("examples");
test "splash assembles boots and produces golden PPM sha256" {
    const a = std.testing.allocator;
    var d: asm16.Diagnostic = .{};
    const r = try asm16.assemble(a, examples.splash, &d);
    defer r.deinit();
    var m: Machine = .{};
    try m.load(r.image);
    for (0..100000) |_| {
        m.step();
        if (m.cpu.halted or m.cpu.trap != null) break;
    }
    try std.testing.expect(m.cpu.halted);
    try std.testing.expect(m.cpu.trap == null);
    const bytes = try video.ppm(a, m.bus.bytes[0xc000..0xd800], &m.bus.palette, m.bus.enabled);
    defer a.free(bytes);
    try std.testing.expectEqual(36878, bytes.len);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    try std.testing.expectEqualStrings("1296533d29754dba185c619f8f87e4437b425deaf23f9297bbbcfffecb7771cb", &std.fmt.bytesToHex(hash, .lower));
}

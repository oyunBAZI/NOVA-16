pub const width = 128;
pub const height = 96;
pub const default_palette = [48]u8{
    0x14, 0x0c, 0x1c, 0x44, 0x24, 0x34, 0x30, 0x34, 0x6d, 0x4e, 0x4a, 0x4e,
    0x85, 0x4c, 0x30, 0x34, 0x65, 0x24, 0xd0, 0x46, 0x48, 0x75, 0x71, 0x61,
    0x59, 0x7d, 0xce, 0xd2, 0x7d, 0x2c, 0x85, 0x95, 0xa1, 0x6d, 0xaa, 0x2c,
    0xd2, 0xaa, 0x99, 0x6d, 0xc2, 0xca, 0xda, 0xd4, 0x5e, 0xde, 0xee, 0xd6,
};
const std = @import("std");
pub const ppm_header = "P6\n128 96\n255\n";
pub fn render(vram: []const u8, palette: *const [48]u8, enabled: bool, out: *[width * height * 3]u8) void {
    for (0..height) |y| {
        for (0..width) |x| {
            const byte = vram[y * 64 + x / 2];
            const index: usize = if (!enabled) 0 else if (x % 2 == 0) byte & 15 else byte >> 4;
            @memcpy(out[(y * width + x) * 3 ..][0..3], palette[index * 3 ..][0..3]);
        }
    }
}
pub fn ppm(a: std.mem.Allocator, vram: []const u8, palette: *const [48]u8, enabled: bool) ![]u8 {
    const out = try a.alloc(u8, ppm_header.len + width * height * 3);
    @memcpy(out[0..ppm_header.len], ppm_header);
    render(vram, palette, enabled, out[ppm_header.len..][0 .. width * height * 3]);
    return out;
}
test "nibble order final pixel palette and display disable" {
    var vram: [6144]u8 = @splat(0);
    var p = default_palette;
    var out: [width * height * 3]u8 = undefined;
    vram[0] = 0x21;
    vram[6143] = 0xf0;
    p[3] = 255;
    render(&vram, &p, true, &out);
    try std.testing.expectEqualSlices(u8, p[3..6], out[0..3]);
    try std.testing.expectEqualSlices(u8, p[6..9], out[3..6]);
    try std.testing.expectEqualSlices(u8, p[45..48], out[out.len - 3 ..]);
    render(&vram, &p, false, &out);
    for (0..width * height) |k| try std.testing.expectEqualSlices(u8, p[0..3], out[k * 3 ..][0..3]);
}

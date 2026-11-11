const std = @import("std");
pub const RomError = error{ TruncatedHeader, BadMagic, BadVersion, BadLength, BadSize, BadFlags, BadReserved, BadEntry, BadChecksum };
pub const Image = struct { payload: []const u8, entry: u16, checksum: u32 };
fn u16le(b: []const u8) u16 {
    return std.mem.readInt(u16, b[0..2], .little);
}
pub fn parse(data: []const u8) RomError!Image {
    if (data.len < 32) return error.TruncatedHeader;
    if (!std.mem.eql(u8, data[0..4], "N16R")) return error.BadMagic;
    if (u16le(data[4..]) != 1) return error.BadVersion;
    const entry = u16le(data[6..]);
    const length = u16le(data[8..]);
    if (length == 0 or length > 8192) return error.BadLength;
    if (data.len != 32 + @as(usize, length)) return error.BadSize;
    if (u16le(data[10..]) != 0) return error.BadFlags;
    for (data[16..32]) |v| {
        if (v != 0) return error.BadReserved;
    }
    if (entry & 1 != 0 or entry >= length) return error.BadEntry;
    const crc = std.mem.readInt(u32, data[12..16], .little);
    if (std.hash.Crc32.hash(data[32..]) != crc) return error.BadChecksum;
    return .{ .payload = data[32..], .entry = entry, .checksum = crc };
}
pub fn pack(allocator: std.mem.Allocator, payload: []const u8, entry: u16) ![]u8 {
    if (payload.len == 0 or payload.len > 8192) return error.BadLength;
    if (entry & 1 != 0 or entry >= payload.len) return error.BadEntry;
    const out = try allocator.alloc(u8, 32 + payload.len);
    @memset(out, 0);
    @memcpy(out[0..4], "N16R");
    std.mem.writeInt(u16, out[4..6], 1, .little);
    std.mem.writeInt(u16, out[6..8], entry, .little);
    std.mem.writeInt(u16, out[8..10], @intCast(payload.len), .little);
    std.mem.writeInt(u32, out[12..16], std.hash.Crc32.hash(payload), .little);
    @memcpy(out[32..], payload);
    return out;
}
test "strict ROM parser rejects corrupt headers payloads and sizes" {
    const a = std.testing.allocator;
    const data = try pack(a, &.{ 0, 0, 1, 0 }, 0);
    defer a.free(data);
    _ = try parse(data);
    for (0..data.len) |k| {
        data[k] ^= 0x80;
        try std.testing.expectError(if (k < 4) error.BadMagic else if (k < 6) error.BadVersion else if (k < 8) error.BadEntry else if (k == 8) error.BadSize else if (k == 9) error.BadLength else if (k < 12) error.BadFlags else if (k < 16 or k >= 32) error.BadChecksum else error.BadReserved, parse(data));
        data[k] ^= 0x80;
    }
    for (0..32) |k| try std.testing.expectError(error.TruncatedHeader, parse(data[0..k]));
    try std.testing.expectError(error.BadSize, parse(data[0..35]));
}

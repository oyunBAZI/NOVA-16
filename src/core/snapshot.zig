//! Portable N16S snapshot V1: explicit little-endian fields, no struct dumps.
const std = @import("std");
const Machine = @import("machine.zig").Machine;
const traps = @import("traps.zig");
const isa = @import("../arch/isa.zig");
pub const payload_size = 128 + 65536 + 48;
pub const file_size = 32 + payload_size;
const faults = [_]traps.Fault{ error.InvalidOpcode, error.Unaligned, error.ExecuteDenied, error.AddressOverflow, error.ReadDenied, error.WriteDenied, error.ReservedBits, error.StackUnderflow, error.StackOverflow, error.InvalidStack, error.InstructionLimit };
fn put(comptime T: type, b: []u8, offset: usize, v: T) void {
    std.mem.writeInt(T, b[offset..][0..@sizeOf(T)], v, .little);
}
fn get(comptime T: type, b: []const u8, offset: usize) T {
    return std.mem.readInt(T, b[offset..][0..@sizeOf(T)], .little);
}
pub fn encode(a: std.mem.Allocator, m: *const Machine) ![]u8 {
    const out = try a.alloc(u8, file_size);
    @memset(out, 0);
    @memcpy(out[0..4], "N16S");
    put(u16, out, 4, 1);
    put(u32, out, 8, payload_size);
    const p = out[32..];
    const c = &m.cpu;
    put(u32, p, 0, m.checksum);
    put(u16, p, 4, m.entry);
    p[6] = c.flags;
    p[7] = @as(u8, @intFromBool(c.halted)) | (@as(u8, @intFromBool(c.paused)) << 1);
    for (c.r, 0..) |r, k| put(u16, p, 8 + k * 2, r);
    put(u16, p, 24, c.pc);
    put(u16, p, 26, c.sp);
    put(u16, p, 28, c.depth);
    put(u64, p, 32, c.retired);
    put(i32, p, 40, c.address);
    put(u16, p, 44, c.instruction);
    p[46] = @backingInt(c.access);
    if (c.trap) |t| {
        for (faults, 1..) |f, k| if (t.kind == f) {
            p[47] = @intCast(k);
            break;
        };
        put(u16, p, 48, t.pc);
        put(u16, p, 50, t.instruction);
        put(i32, p, 52, t.address);
        p[56] = @backingInt(t.access);
    }
    p[57] = m.bus.input.held;
    p[58] = m.bus.input.pressed;
    p[59] = @intFromBool(m.bus.enabled);
    put(u16, p, 60, m.bus.frame);
    p[62] = @intFromBool(m.bus.vblank);
    put(u16, p, 64, m.rom_length);
    @memcpy(p[128..][0..65536], &m.bus.bytes);
    @memcpy(p[128 + 65536 ..], &m.bus.palette);
    put(u32, out, 12, std.hash.Crc32.hash(p));
    return out;
}
/// All validation completes in a bounded temporary machine before assignment.
pub fn restore(target: *Machine, data: []const u8, expected_rom: ?u32) !void {
    if (data.len != file_size) return error.SnapshotSize;
    if (!std.mem.eql(u8, data[0..4], "N16S")) return error.SnapshotMagic;
    if (get(u16, data, 4) != 1) return error.SnapshotVersion;
    if (get(u16, data, 6) != 0 or get(u32, data, 8) != payload_size) return error.SnapshotHeader;
    for (data[16..32]) |v| if (v != 0) return error.SnapshotReserved;
    const p = data[32..];
    if (std.hash.Crc32.hash(p) != get(u32, data, 12)) return error.SnapshotChecksum;
    if (p[6] > 15 or p[7] > 3 or p[46] > 4 or p[47] > faults.len or p[56] > 4 or p[59] > 1 or p[62] > 1) return error.SnapshotState;
    if (p[30] != 0 or p[31] != 0 or p[63] != 0) return error.SnapshotReserved;
    for (p[66..128]) |v| if (v != 0) return error.SnapshotReserved;
    var m: Machine = .{};
    m.checksum = get(u32, p, 0);
    m.entry = get(u16, p, 4);
    m.rom_length = get(u16, p, 64);
    if (expected_rom) |crc| if (crc != m.checksum) return error.SnapshotRomMismatch;
    if (m.rom_length > isa.rom_size or m.entry & 1 != 0 or (m.rom_length != 0 and m.entry >= m.rom_length)) return error.SnapshotState;
    const c = &m.cpu;
    c.flags = @intCast(p[6]);
    c.halted = p[7] & 1 != 0;
    c.paused = p[7] & 2 != 0;
    for (&c.r, 0..) |*r, k| r.* = get(u16, p, 8 + k * 2);
    c.pc = get(u16, p, 24);
    c.sp = get(u16, p, 26);
    c.depth = get(u16, p, 28);
    c.retired = get(u64, p, 32);
    if (c.depth > isa.stack_capacity or c.sp != isa.stack_top - @as(u32, c.depth) * 2) return error.SnapshotState;
    c.address = get(i32, p, 40);
    c.instruction = get(u16, p, 44);
    c.access = @fromBackingInt(@intCast(p[46]));
    if (p[47] != 0) c.trap = .{ .kind = faults[p[47] - 1], .pc = get(u16, p, 48), .instruction = get(u16, p, 50), .address = get(i32, p, 52), .access = @fromBackingInt(@intCast(p[56])) } else for (p[48..57]) |v| if (v != 0) return error.SnapshotReserved;
    if (c.pc & 1 != 0 and c.trap == null) return error.SnapshotState;
    m.bus.input.held = p[57];
    m.bus.input.pressed = p[58];
    m.bus.enabled = p[59] == 1;
    m.bus.frame = get(u16, p, 60);
    m.bus.vblank = p[62] == 1;
    @memcpy(&m.bus.bytes, p[128..][0..65536]);
    @memcpy(&m.bus.palette, p[128 + 65536 ..]);
    const rom = m.bus.bytes[isa.rom_base..];
    if (m.rom_length == 0) {
        if (m.checksum != 0 or m.entry != 0) return error.SnapshotState;
    } else if (std.hash.Crc32.hash(rom[0..m.rom_length]) != m.checksum) return error.SnapshotRomMismatch;
    for (rom[m.rom_length..]) |v| if (v != 0) return error.SnapshotState;
    target.* = m;
}
test "full-state snapshots roundtrip deterministically and malformed restore is atomic" {
    const a = std.testing.allocator;
    const rom = @import("../rom/format.zig");
    const image = try rom.pack(a, &.{ 0xff, 0xd0 }, 0);
    defer a.free(image);
    var m: Machine = .{};
    try m.load(image);
    m.frame(19, 100);
    m.bus.palette[2] = 88;
    m.bus.bytes[0xc000] = 0x12;
    m.bus.input.pressed = 3;
    const saved = try encode(a, &m);
    defer a.free(saved);
    var restored: Machine = .{};
    try restore(&restored, saved, m.checksum);
    const again = try encode(a, &restored);
    defer a.free(again);
    try std.testing.expectEqualSlices(u8, saved, again);
    m.frame(0, 1000);
    restored.frame(0, 1000);
    const x = try encode(a, &m);
    defer a.free(x);
    const y = try encode(a, &restored);
    defer a.free(y);
    try std.testing.expectEqualSlices(u8, x, y);
    saved[100] ^= 1;
    try std.testing.expectError(error.SnapshotChecksum, restore(&restored, saved, null));
    saved[100] ^= 1;
    try std.testing.expectError(error.SnapshotRomMismatch, restore(&restored, saved, 1));
    put(u16, saved[32..], 28, 65535);
    put(u32, saved, 12, std.hash.Crc32.hash(saved[32..]));
    try std.testing.expectError(error.SnapshotState, restore(&restored, saved, null));
    const unchanged = try encode(a, &restored);
    defer a.free(unchanged);
    try std.testing.expectEqualSlices(u8, y, unchanged);
}
test "snapshot at maximum retirement cannot overflow host counter" {
    const a = std.testing.allocator;
    var m: Machine = .{};
    m.cpu.retired = std.math.maxInt(u64);
    const data = try encode(a, &m);
    defer a.free(data);
    var copy: Machine = .{};
    try restore(&copy, data, null);
    copy.step();
    try std.testing.expectEqual(error.InstructionLimit, copy.cpu.trap.?.kind);
}

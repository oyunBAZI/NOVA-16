//! Portable N16S snapshots V1/V2: explicit little-endian fields, no struct dumps.
const std = @import("std");
const Machine = @import("machine.zig").Machine;
const traps = @import("traps.zig");
const isa = @import("../arch/isa.zig");
pub const payload_size = 128 + 65536 + 48;
pub const file_size = 32 + payload_size;
pub const v2_file_size = 67680;
const faults = [_]traps.Fault{ error.InvalidOpcode, error.Unaligned, error.ExecuteDenied, error.AddressOverflow, error.ReadDenied, error.WriteDenied, error.ReservedBits, error.StackUnderflow, error.StackOverflow, error.InvalidStack, error.InstructionLimit, error.InvalidInterruptState, error.InterruptNesting, error.ClockLimit, error.DeviceValue };
fn put(comptime T: type, b: []u8, offset: usize, v: T) void {
    std.mem.writeInt(T, b[offset..][0..@sizeOf(T)], v, .little);
}
fn get(comptime T: type, b: []const u8, offset: usize) T {
    return std.mem.readInt(T, b[offset..][0..@sizeOf(T)], .little);
}
pub fn encode(a: std.mem.Allocator, m: *const Machine) ![]u8 {
    if (m.bus.profile == .v2) return encodeV2(a, m);
    return encodeV1(a, m);
}
fn encodeV1(a: std.mem.Allocator, m: *const Machine) ![]u8 {
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
/// Checked serialization for embedders; raw encode remains a forensic interface.
pub fn encodeChecked(a: std.mem.Allocator, m: *const Machine) ![]u8 {
    try m.validateState();
    if (m.bus.profile == .v1) if (m.cpu.trap) |trap| {
        for (faults[11..]) |fault| if (fault == trap.kind) return error.InvalidV1State;
    };
    return encode(a, m);
}
/// All validation completes in a bounded temporary machine before assignment.
pub fn restore(target: *Machine, data: []const u8, expected_rom: ?u32) !void {
    if (data.len >= 6 and get(u16, data, 4) == 2) {
        if (target.bus.profile != .v2) return error.SnapshotProfile;
        return restoreV2(target, data, expected_rom);
    }
    if (target.bus.profile != .v1) return error.SnapshotProfile;
    if (data.len == file_size and data[32 + 47] > 11) return error.SnapshotState;
    return restoreV1(target, data, expected_rom);
}
fn restoreV1(target: *Machine, data: []const u8, expected_rom: ?u32) !void {
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
    m.validateState() catch return error.SnapshotState;
    target.* = m;
}
const Section = struct { tag: *const [4]u8, offset: usize, length: usize };
const sections = [_]Section{
    .{ .tag = "CPU2", .offset = 112, .length = 160 },
    .{ .tag = "MEM1", .offset = 272, .length = 65584 },
    .{ .tag = "AUD1", .offset = 65856, .length = 1696 },
    .{ .tag = "IRQ1", .offset = 67552, .length = 128 },
};
fn encodeV2(a: std.mem.Allocator, m: *const Machine) ![]u8 {
    const base = try encodeV1(a, m);
    defer a.free(base);
    const out = try a.alloc(u8, v2_file_size);
    @memset(out, 0);
    @memcpy(out[0..4], "N16S");
    put(u16, out, 4, 2);
    put(u32, out, 8, v2_file_size);
    put(u16, out, 16, 2);
    put(u16, out, 18, 4);
    put(u32, out, 20, 32);
    const cpu = out[112..272];
    @memcpy(cpu[0..128], base[32..160]);
    put(u64, cpu, 128, m.slots);
    put(u64, cpu, 136, m.irq_entries);
    put(u16, cpu, 144, @intCast(m.slots % 20000));
    put(u16, cpu, 146, m.bus.audio.prefix);
    cpu[148] = @intCast(m.slots % 25);
    @memcpy(out[272..65856], base[160..]);
    const audio = out[65856..67552];
    const sound = &m.bus.audio;
    audio[0] = @intFromBool(sound.enabled);
    audio[1] = sound.gain;
    put(u64, audio, 8, sound.generated);
    for (sound.voices, 0..) |v, i| {
        const offset = 32 + i * 16;
        put(u32, audio, offset, v.step);
        put(u32, audio, offset + 4, v.phase);
        put(u16, audio, offset + 8, v.noise);
        audio[offset + 10] = v.volume;
        audio[offset + 11] = v.wave;
        audio[offset + 12] = @intFromBool(v.enabled);
    }
    for (sound.pcm, 0..) |sample, i| put(i16, audio, 96 + i * 2, sample);
    const irq = out[67552..];
    const controller = &m.bus.irq;
    irq[0] = controller.pending;
    irq[1] = controller.mask;
    irq[2] = @intFromBool(controller.ie);
    irq[3] = controller.depth;
    put(u32, irq, 4, controller.period);
    put(u32, irq, 8, controller.remaining);
    irq[12] = @intFromBool(controller.reload);
    for (controller.frames, 0..) |frame, i| {
        put(u16, irq, 16 + 12 * i, frame.top);
        irq[18 + 12 * i] = frame.vector;
    }
    for (sections, 0..) |section, i| {
        const d = out[32 + i * 20 ..][0..20];
        @memcpy(d[0..4], section.tag);
        put(u32, d, 4, @intCast(section.offset));
        put(u32, d, 8, @intCast(section.length));
        put(u32, d, 12, std.hash.Crc32.hash(out[section.offset..][0..section.length]));
    }
    put(u32, out, 12, std.hash.Crc32.hash(out[32..]));
    return out;
}
fn zero(bytes: []const u8) !void {
    for (bytes) |byte| if (byte != 0) return error.SnapshotReserved;
}
fn restoreV2(target: *Machine, data: []const u8, expected_rom: ?u32) !void {
    if (data.len != v2_file_size) return error.SnapshotSize;
    if (!std.mem.eql(u8, data[0..4], "N16S")) return error.SnapshotMagic;
    if (get(u16, data, 6) != 0 or get(u32, data, 8) != v2_file_size or get(u16, data, 16) != 2 or get(u16, data, 18) != 4 or get(u32, data, 20) != 32) return error.SnapshotHeader;
    try zero(data[24..32]);
    if (std.hash.Crc32.hash(data[32..]) != get(u32, data, 12)) return error.SnapshotChecksum;
    for (sections, 0..) |section, i| {
        const d = data[32 + i * 20 ..][0..20];
        if (!std.mem.eql(u8, d[0..4], section.tag) or get(u32, d, 4) != section.offset or get(u32, d, 8) != section.length) return error.SnapshotHeader;
        try zero(d[16..20]);
        if (get(u32, d, 12) != std.hash.Crc32.hash(data[section.offset..][0..section.length])) return error.SnapshotChecksum;
    }
    // Reuse the V1 metadata/memory validator without changing its wire bytes.
    var base: [file_size]u8 = @splat(0);
    @memcpy(base[0..4], "N16S");
    put(u16, &base, 4, 1);
    put(u32, &base, 8, payload_size);
    @memcpy(base[32..160], data[112..240]);
    @memcpy(base[160..], data[272..65856]);
    put(u32, &base, 12, std.hash.Crc32.hash(base[32..]));
    var m: Machine = .{};
    try restoreV1(&m, &base, expected_rom);
    if (m.rom_length == 0 or target.rom_length == 0 or m.checksum != target.checksum) return error.SnapshotRomMismatch;
    m.bus.profile = .v2;
    const cpu = data[112..272];
    m.slots = get(u64, cpu, 128);
    m.irq_entries = get(u64, cpu, 136);
    if (get(u16, cpu, 144) != m.slots % 20000 or get(u16, cpu, 146) != (m.slots % 20000) / 25 or cpu[148] != m.slots % 25) return error.SnapshotState;
    try zero(cpu[149..160]);
    const audio = data[65856..67552];
    if (audio[0] > 1) return error.SnapshotState;
    try zero(audio[2..8]);
    try zero(audio[16..32]);
    const sound = &m.bus.audio;
    sound.enabled = audio[0] != 0;
    sound.gain = audio[1];
    sound.generated = get(u64, audio, 8);
    sound.prefix = get(u16, cpu, 146);
    for (&sound.voices, 0..) |*v, i| {
        const offset = 32 + i * 16;
        v.step = get(u32, audio, offset);
        v.phase = get(u32, audio, offset + 4);
        v.noise = get(u16, audio, offset + 8);
        v.volume = audio[offset + 10];
        v.wave = audio[offset + 11];
        if (audio[offset + 12] > 1) return error.SnapshotState;
        v.enabled = audio[offset + 12] != 0;
        try zero(audio[offset + 13 ..][0..3]);
    }
    for (&sound.pcm, 0..) |*sample, i| sample.* = get(i16, audio, 96 + i * 2);
    const irq = data[67552..];
    if (irq[2] > 1 or irq[12] > 1) return error.SnapshotState;
    try zero(irq[13..16]);
    try zero(irq[112..128]);
    const controller = &m.bus.irq;
    controller.pending = irq[0];
    controller.mask = irq[1];
    controller.ie = irq[2] != 0;
    controller.depth = irq[3];
    controller.period = get(u32, irq, 4);
    controller.remaining = get(u32, irq, 8);
    controller.reload = irq[12] != 0;
    for (&controller.frames, 0..) |*frame, i| {
        const offset = 16 + 12 * i;
        frame.top = get(u16, irq, offset);
        frame.vector = irq[offset + 2];
        try zero(irq[offset + 3 ..][0..9]);
    }
    m.validateState() catch return error.SnapshotState;
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
    // Byte-protocol vector independently encoded with Python struct/zlib.
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(saved, &hash, .{});
    try std.testing.expectEqualStrings("6509420edf13f7d12f32eb26a6940e120f9c1b9685ecb10685be456fb04532af", &std.fmt.bytesToHex(hash, .lower));
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

test "every trap code and context roundtrips without native enum serialization" {
    const a = std.testing.allocator;
    for (faults[0..11]) |fault| {
        var m: Machine = .{};
        m.cpu.trap = .{ .kind = fault, .pc = 0xe001, .instruction = 0xffff, .address = -32, .access = .write };
        const bytes = try encode(a, &m);
        defer a.free(bytes);
        var restored: Machine = .{};
        try restore(&restored, bytes, null);
        try std.testing.expectEqualDeep(m.cpu.trap, restored.cpu.trap);
        const again = try encode(a, &restored);
        defer a.free(again);
        try std.testing.expectEqualSlices(u8, bytes, again);
    }
}
test "CRC-correct invalid metadata and version failures leave live state unchanged" {
    const a = std.testing.allocator;
    var original: Machine = .{};
    try original.patch(0x100, &.{ 42, 99 });
    const saved = try encode(a, &original);
    defer a.free(saved);
    // Exact serialized offsets: version, reserved header, flags, stop bits,
    // enum tags, trap code, booleans, reserved payload and inconsistent depth.
    for ([_]usize{ 4, 6, 16, 32 + 6, 32 + 7, 32 + 46, 32 + 47, 32 + 56, 32 + 59, 32 + 62, 32 + 66, 32 + 28 }) |offset| {
        const bytes = try a.dupe(u8, saved);
        defer a.free(bytes);
        bytes[offset] = 255;
        put(u32, bytes, 12, std.hash.Crc32.hash(bytes[32..]));
        var live = original;
        if (restore(&live, bytes, null)) |_| return error.ExpectedSnapshotRejection else |_| {}
        const after = try encode(a, &live);
        defer a.free(after);
        try std.testing.expectEqualSlices(u8, saved, after);
    }
}

test "CRC-correct active non-executable PC rejects atomically" {
    const a = std.testing.allocator;
    var original: Machine = .{};
    try original.patch(0x120, &.{ 42, 99 });
    const bytes = try encode(a, &original);
    defer a.free(bytes);
    put(u16, bytes[32..], 24, 0xc000);
    put(u32, bytes, 12, std.hash.Crc32.hash(bytes[32..]));
    var live = original;
    try std.testing.expectError(error.SnapshotState, restore(&live, bytes, null));
    try std.testing.expectEqualDeep(original.cpu, live.cpu);
    try std.testing.expectEqualSlices(u8, &original.bus.bytes, &live.bus.bytes);
}

test "snapshot PC stop-state matrix, ROM metadata and checked embedding remain atomic" {
    const a = std.testing.allocator;
    for ([_]u16{ 0, 1, 0xbffe, 0xbfff, 0xc000, 0xd7fe, 0xd800, 0xdffe, 0xe000, 0xe001, 0xfffe, 0xffff }) |pc| {
        for (0..8) |bits| {
            var m: Machine = .{};
            m.cpu.pc = pc;
            m.cpu.halted = bits & 1 != 0;
            m.cpu.paused = bits & 2 != 0;
            if (bits & 4 != 0) m.cpu.trap = .{ .kind = error.ExecuteDenied, .pc = pc, .address = pc, .access = .fetch };
            const valid = m.cpu.trap != null or (pc & 1 == 0 and (m.cpu.halted or m.cpu.paused or isa.executable(pc)));
            const bytes = try encode(a, &m);
            defer a.free(bytes);
            var live: Machine = .{};
            live.cpu.r[3] = 1234;
            const before = live.cpu;
            if (valid) try restore(&live, bytes, null) else {
                try std.testing.expectError(error.SnapshotState, restore(&live, bytes, null));
                try std.testing.expectEqualDeep(before, live.cpu);
            }
        }
    }
    var m: Machine = .{};
    var cpu = m.cpu;
    cpu.pc = 0xc000;
    try std.testing.expectError(error.ExecuteDenied, m.replaceCpu(cpu));
    try std.testing.expectEqual(0xe000, m.cpu.pc);
    m.cpu = cpu;
    try std.testing.expectError(error.ExecuteDenied, encodeChecked(a, &m));
    try m.resetChecked();
    m.rom_length = 8193;
    const before = m.cpu;
    try std.testing.expectError(error.InvalidRomState, m.resetChecked());
    try std.testing.expectEqualDeep(before, m.cpu);
    m.rom_length = 0;
    m.bus.bytes[0xffff] = 1;
    try std.testing.expectError(error.InvalidRomState, m.validateState());
}

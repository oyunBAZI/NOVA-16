const std = @import("std");
const t = std.testing;
const Machine = @import("core/machine.zig").Machine;
const Bus = @import("core/bus.zig").Bus;
const rom = @import("rom/format.zig");
const assembler = @import("asm/assembler.zig");
const snap = @import("core/snapshot.zig");
const isa = @import("arch/isa.zig");
fn machine(source: []const u8) !Machine {
    var diagnostic: assembler.Diagnostic = .{};
    const result = try assembler.assembleProfile(t.allocator, source, &diagnostic, .v2);
    defer result.deinit();
    var m: Machine = .{};
    try m.load(result.image);
    return m;
}
fn fixture(name: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, @import("v2-contract").json, .{});
    defer parsed.deinit();
    const encoded = parsed.value.object.get(name).?.object.get("base64").?.string;
    const decoder = std.base64.standard.Decoder;
    const bytes = try t.allocator.alloc(u8, try decoder.calcSizeForSlice(encoded));
    errdefer t.allocator.free(bytes);
    try decoder.decode(bytes, encoded);
    return bytes;
}
fn identical(a: *const Machine, b: *const Machine) !void {
    const x = try snap.encode(t.allocator, a);
    defer t.allocator.free(x);
    const y = try snap.encode(t.allocator, b);
    defer t.allocator.free(y);
    try t.expectEqualSlices(u8, x, y);
}
fn put(comptime T: type, bytes: []u8, offset: usize, value: T) void {
    std.mem.writeInt(T, bytes[offset..][0..@sizeOf(T)], value, .little);
}
fn checksums(bytes: []u8) void {
    for ([_]usize{ 112, 272, 65856, 67552 }, [_]usize{ 160, 65584, 1696, 128 }, 0..) |offset, length, i|
        put(u32, bytes, 32 + i * 20 + 12, std.hash.Crc32.hash(bytes[offset..][0..length]));
    put(u32, bytes, 12, std.hash.Crc32.hash(bytes[32..]));
}
test "V2 explicit profile containers match independent ROM bytes and reject atomically" {
    const golden = try fixture("rom2_halt");
    defer t.allocator.free(golden);
    const container = try rom.packProfile(t.allocator, &.{ 1, 0 }, 0, .v2);
    defer t.allocator.free(container);
    try t.expectEqualSlices(u8, golden, container);
    var m = try machine("LDI R0, 42\nHALT");
    m.step();
    const before = m;
    for ([_]usize{ 0, 4, 6, 8, 10, 12, 16, 18, 20, 31, 32 }) |offset| {
        const bad = try t.allocator.dupe(u8, golden);
        defer t.allocator.free(bad);
        bad[offset] ^= 0x80;
        if (m.load(bad)) |_| return error.ExpectedRejection else |_| {}
        try identical(&before, &m);
    }
    for (0..golden.len) |length| {
        if (m.load(golden[0..length])) |_| return error.ExpectedRejection else |_| {}
        try identical(&before, &m);
    }
    for ([_]u16{ 0, 1, 2, 4, 7, 0xffff }) |features| {
        put(u16, container, 18, features);
        try t.expectError(error.BadFeatures, rom.parse(container));
    }
    put(u16, container, 18, 3);
    put(u16, container, 16, 1);
    try t.expectError(error.BadProfile, rom.parse(container));
    put(u16, container, 4, 1);
    try t.expectError(error.BadReserved, rom.parse(container));
    const large = try t.allocator.alloc(u8, 8193);
    defer t.allocator.free(large);
    try t.expectError(error.BadLength, rom.packProfile(t.allocator, large, 0, .v2));
}
test "V2 encoding adds exactly three system words and default assembler stays V1" {
    for (0..65536) |raw| {
        const word: u16 = @intCast(raw);
        if (isa.decodeProfile(word, .v2)) |decoded| {
            if (word >= 6 and word <= 8) try t.expectEqual(0, decoded.major) else try t.expectEqualDeep(try isa.decode(word), decoded);
        } else |_| try t.expectError(error.InvalidOpcode, isa.decode(word));
    }
    var diagnostic: assembler.Diagnostic = .{};
    for ([_][]const u8{ "EI", "DI", "IRET" }, 6..) |name, word| {
        try t.expectError(error.UnknownMnemonic, assembler.assemble(t.allocator, name, &diagnostic));
        const result = try assembler.assembleProfile(t.allocator, name, &diagnostic, .v2);
        defer result.deinit();
        var output: [32]u8 = undefined;
        var writer = std.Io.Writer.fixed(&output);
        _ = try @import("debug/disasm.zig").instructionProfile(&writer, @intCast(word), null, 0xe000, .v2);
        try t.expectEqualStrings(name, writer.buffered());
        const v1 = try rom.pack(t.allocator, result.image[32..], 0);
        defer t.allocator.free(v1);
        var m: Machine = .{};
        try m.load(v1);
        m.step();
        try t.expectEqual(error.InvalidOpcode, m.cpu.trap.?.kind);
        try t.expectEqual(0, m.slots);
    }
}
test "V2 all device permissions are explicit and V1 denies every new register" {
    var v1: Bus = .{};
    var v2: Bus = .{ .profile = .v2 };
    for (0xd900..0xd970) |raw| {
        const address: u16 = @intCast(raw);
        try t.expectError(error.ReadDenied, v1.read8(address));
        try t.expectError(error.WriteDenied, v1.write8(address, 0));
        const voice_read = address < 0xd940 and ((address & 15) <= 6 or ((address & 15) >= 8 and (address & 15) <= 13));
        const voice_write = address < 0xd940 and (address & 15) <= 6;
        const readable = voice_read or (address >= 0xd940 and address <= 0xd945) or (address >= 0xd950 and address <= 0xd953) or (address >= 0xd960 and address <= 0xd968);
        const writable = voice_write or (address >= 0xd940 and address <= 0xd941) or (address >= 0xd950 and address <= 0xd951) or (address >= 0xd960 and address <= 0xd963) or address == 0xd968;
        if (readable) _ = try v2.read8(address) else try t.expectError(error.ReadDenied, v2.read8(address));
        if (writable) try v2.write8(address, 0) else try t.expectError(error.WriteDenied, v2.write8(address, 0));
    }
    try v2.write16(0xd900, 0xffff);
    try v2.write16(0xd902, 0x7fff);
    try t.expectError(error.DeviceValue, v2.write16(0xd902, 0x8000));
    try t.expectEqual(0x7fffffff, v2.audio.voices[0].step);
    try v2.write16(0xd900, 0);
    try v2.write16(0xd902, 0x8000);
    try t.expectEqual(0x80000000, v2.audio.voices[0].step);
    const before = v2.audio;
    try t.expectError(error.WriteDenied, v2.write16(0xd906, 3));
    try t.expectError(error.DeviceValue, v2.write16(0xd904, 0x04ff));
    try t.expectError(error.ReservedBits, v2.write8(0xd906, 4));
    try t.expectError(error.ReservedBits, v2.write16(0xd940, 0x0104));
    try t.expectEqualDeep(before, v2.audio);
    v2.irq.pending = 3;
    try t.expectError(error.ReservedBits, v2.write16(0xd950, 0x0401));
    try t.expectEqual(3, v2.irq.pending);
    try t.expectEqual(0, v2.irq.mask);
    try v2.write16(0xd950, 0x0201);
    try t.expectEqual(2, v2.irq.pending);
    try t.expectEqual(2, v2.irq.mask);
    try t.expectEqual(0xff00, try v2.read16(0xd952));
}
test "V2 hardware PCM matches complete independent 800 sample vector" {
    var m = try machine("HALT");
    try m.bus.write8(0xd940, 1);
    try m.bus.write8(0xd941, 193);
    for ([_]u8{ 255, 127, 200, 64 }, 0..) |volume, i| {
        const base: u16 = @intCast(0xd900 + 16 * i);
        try m.bus.write16(base + 2, 0x4000);
        try m.bus.write16(base + 4, @as(u16, volume) | (@as(u16, @intCast(i)) << 8));
        try m.bus.write8(base + 6, 1);
        // The normative mixer vector supplies this seed for every voice.
        m.bus.audio.voices[i].noise = 0xace2;
    }
    var output: [800]i16 = undefined;
    try t.expect(m.frameAudio(0, std.math.maxInt(u64), &output));
    const vectors = @import("experimental/audio_vectors.zig");
    try t.expectEqualSlices(i16, &vectors.first, output[0..vectors.first.len]);
    const wav = try @import("devices/audio.zig").wav(t.allocator, &output);
    defer t.allocator.free(wav);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(wav[44..], &hash, .{});
    try t.expectEqualSlices(u8, &vectors.sha256, &hash);
    try t.expectEqual(20000, m.slots);
    try t.expectEqual(800, m.bus.audio.generated);
    try t.expectEqual(1, m.cpu.retired);
    try t.expectEqual(0, m.bus.audio.prefix);
    try t.expectEqual(1, m.bus.irq.pending);
}
test "V2 sample boundaries mute freeze reset strobes and deterministic partial frames" {
    var m = try machine("loop: B.AL loop");
    try m.bus.write16(0xd902, 0x4000);
    try m.bus.write8(0xd904, 255);
    try m.bus.write8(0xd906, 1);
    for (0..24) |_| m.step();
    try t.expectEqual(0, m.bus.audio.generated);
    m.step();
    try t.expectEqual(1, m.bus.audio.generated);
    try t.expectEqual(0, m.bus.audio.voices[0].phase); // master disabled freezes
    try m.bus.write16(0xd940, 1); // gain zero, master on
    for (0..25) |_| m.step();
    try t.expectEqual(0x40000000, m.bus.audio.voices[0].phase);
    try t.expectEqual(0, m.bus.audio.pcm[1]);
    try m.bus.write8(0xd941, 255);
    for (0..25) |_| m.step();
    try t.expectEqual(8191, m.bus.audio.pcm[2]);
    try m.bus.write8(0xd906, 3);
    try t.expectEqual(0, m.bus.audio.voices[0].phase);
    try t.expectEqual(1, try m.bus.read8(0xd906));
    try t.expectEqual(3, m.bus.audio.generated);
    try m.bus.write8(0xd940, 3);
    try t.expectEqual(255, m.bus.audio.gain);
    const before = m;
    var x: [800]i16 = undefined;
    try t.expect(m.frameAudio(0, 100000, &x));
    var copy = before;
    var y: [800]i16 = undefined;
    try t.expect(copy.frameAudio(0, 100000, &y));
    try t.expectEqualSlices(i16, &x, &y);
    try identical(&m, &copy);
}
test "V2 timer period3 reload independent trace and atomic period rearm" {
    var m = try machine("loop: B.AL loop");
    try m.bus.write16(0xd960, 3);
    try m.bus.write8(0xd968, 1);
    for ([_]u32{ 2, 1, 3, 2, 1, 3, 2, 1 }, 1..) |remaining, slot| {
        m.step();
        if (slot == 5) try m.bus.write8(0xd950, 2);
        try t.expectEqual(remaining, m.bus.irq.remaining);
        try t.expectEqual(@as(u8, if (slot < 3 or slot == 5) 0 else 2), m.bus.irq.pending);
    }
    try m.bus.write16(0xd960, 3);
    try t.expectEqual(3, m.bus.irq.remaining);
    try m.bus.write8(0xd968, 0);
    for (0..5) |_| m.step();
    try t.expectEqual(0, m.bus.irq.remaining);
    try m.bus.write8(0xd960, 3);
    try t.expectEqual(3, m.bus.irq.remaining);
    try m.bus.write16(0xd962, 1);
    try t.expectEqual(65539, m.bus.irq.remaining);
    try t.expectError(error.WriteDenied, m.bus.write16(0xd968, 0));
    try t.expect(!m.bus.irq.reload);
}
test "V2 real guest timer handler executes EI DI IRET and preserves registers" {
    var m = try machine("LDI R0, handler\nLDI R1, 0x42\nSTW R0, [R1]\nLDI R0, 1\nLDI R1, 0xd951\nSTB R0, [R1]\nLDI R0, 30\nLDI R1, 0xd960\nSTW R0, [R1]\nEI\nloop: B.AL loop\nhandler: PUSH R0\nLDI R0, 0xc000\nSTB R0, [R0]\nPOP R0\nINC R2\nIRET\n");
    for (0..90) |_| m.step();
    try t.expectEqual(null, m.cpu.trap);
    try t.expectEqual(1, m.cpu.r[2]);
    try t.expectEqual(1, m.irq_entries);
    try t.expectEqual(0, m.bus.irq.depth);
    try t.expect(m.bus.irq.ie);
    try t.expectEqual(30, m.cpu.r[0]);
    try t.expectEqual(90, m.slots);
    try t.expectEqual(89, m.cpu.retired);
}
test "V2 IRQ priority entry bytes IRET and nested frame continuation" {
    var m = try machine(".org 0xe012\nloop: B.AL loop\n.org 0xe020\nIRET");
    m.cpu.pc = 0xe012;
    m.cpu.flags = 5;
    m.bus.irq.ie = true;
    m.bus.irq.pending = 3;
    m.bus.irq.mask = 0;
    try m.bus.write16(0x40, 0xe020);
    try m.bus.write16(0x42, 0xe020);
    m.step();
    try t.expectEqualSlices(u8, &.{ 1, 0, 5, 0, 0x12, 0xe0 }, m.bus.bytes[0xbff8..0xbffe]);
    try t.expectEqual(2, m.bus.irq.pending);
    try t.expectEqual(0, m.cpu.retired);
    try t.expectEqual(0, m.bus.irq.active());
    m.step();
    try t.expectEqual(0xe012, m.cpu.pc);
    try t.expectEqual(5, m.cpu.flags);
    try t.expectEqual(0xbffe, m.cpu.sp);
    try t.expect(m.bus.irq.ie);
    m.step();
    try t.expectEqual(1, m.bus.irq.active());
    m.bus.irq.ie = true;
    m.bus.irq.pending = 1;
    m.step();
    try t.expectEqual(2, m.bus.irq.depth);
    const saved = try snap.encodeChecked(t.allocator, &m);
    defer t.allocator.free(saved);
    var copy = m;
    try snap.restore(&copy, saved, m.checksum);
    for (0..20) |_| {
        m.step();
        copy.step();
    }
    try identical(&m, &copy);
}
test "V2 IRQ entry faults leave RAM pending IE nesting and registers unchanged" {
    for (0..4) |case| {
        var m = try machine("loop: B.AL loop");
        m.bus.irq.ie = true;
        m.bus.irq.mask = 0;
        m.bus.irq.pending = 3;
        try m.bus.write16(0x40, if (case == 0) 0xe001 else if (case == 1) 0xc000 else 0xe000);
        if (case == 2) {
            m.cpu.sp = 4;
            m.cpu.depth = (0xbffe - 4) / 2;
        }
        if (case == 3) m.bus.irq.depth = 8;
        const before = m;
        m.step();
        try t.expectEqual(([_]@import("core/traps.zig").Fault{ error.Unaligned, error.ExecuteDenied, error.StackOverflow, error.InterruptNesting })[case], m.cpu.trap.?.kind);
        try t.expectEqualSlices(u8, &before.bus.bytes, &m.bus.bytes);
        try t.expectEqualDeep(before.bus.irq, m.bus.irq);
        try t.expectEqualDeep(before.cpu.r, m.cpu.r);
        try t.expectEqual(before.cpu.pc, m.cpu.pc);
        try t.expectEqual(before.cpu.sp, m.cpu.sp);
        try t.expectEqual(0, m.irq_entries);
        try t.expectEqual(1, m.slots);
        try t.expectEqual(0, m.cpu.trap.?.instruction);
    }
}
test "V2 corrupted IRET validates full frame before popping" {
    for (0..6) |case| {
        var m = try machine("IRET");
        m.bus.irq.ie = true;
        m.bus.irq.mask = 0;
        m.bus.irq.pending = 1;
        try m.bus.write16(0x40, 0xe000);
        m.step();
        switch (case) {
            0 => try m.bus.write16(m.cpu.sp, 2),
            1 => try m.bus.write16(m.cpu.sp + 2, 16),
            2 => try m.bus.write16(m.cpu.sp + 4, 0xe001),
            3 => try m.bus.write16(m.cpu.sp + 4, 0xc000),
            4 => {
                m.cpu.sp -= 2;
                m.cpu.depth += 1;
            },
            5 => m.bus.irq.depth = 0,
            else => unreachable,
        }
        const before = m;
        m.step();
        try t.expect(m.cpu.trap != null);
        try t.expectEqual(before.cpu.sp, m.cpu.sp);
        try t.expectEqual(before.cpu.depth, m.cpu.depth);
        try t.expectEqual(before.cpu.pc, m.cpu.pc);
        try t.expectEqual(before.cpu.flags, m.cpu.flags);
        try t.expectEqualDeep(before.bus.irq, m.bus.irq);
        try t.expectEqualSlices(u8, &before.bus.bytes, &m.bus.bytes);
    }
}
test "V2 exact independent snapshots restore and reencode without fixture drift" {
    const image = try fixture("rom2_halt");
    defer t.allocator.free(image);
    for ([_][]const u8{ "snapshot2_idle137", "snapshot2_boundary20000" }) |name| {
        const bytes = try fixture(name);
        defer t.allocator.free(bytes);
        var m: Machine = .{};
        try m.load(image);
        try snap.restore(&m, bytes, m.checksum);
        const encoded = try snap.encodeChecked(t.allocator, &m);
        defer t.allocator.free(encoded);
        try t.expectEqualSlices(u8, bytes, encoded);
        var copy = m;
        var pcm: [800]i16 = undefined;
        try t.expect(m.frameAudio(0, 10000, &pcm));
        var other: [800]i16 = undefined;
        try t.expect(copy.frameAudio(0, 10000, &other));
        try t.expectEqualSlices(i16, &pcm, &other);
        try identical(&m, &copy);
    }
}
test "V2 CRC-correct snapshot corruption rejects atomically across every section" {
    const source = try fixture("snapshot2_idle137");
    defer t.allocator.free(source);
    var m = try machine("HALT");
    try snap.restore(&m, source, m.checksum);
    const before = m;
    for ([_]usize{ 16, 18, 20, 24, 32, 36, 40, 48, 112 + 6, 112 + 30, 112 + 128, 112 + 136, 112 + 144, 112 + 146, 112 + 148, 112 + 149, 65856, 65856 + 2, 65856 + 8, 65856 + 35, 65856 + 40, 65856 + 43, 65856 + 44, 65856 + 45, 65856 + 96 + 10, 67552, 67553, 67554, 67555, 67560, 67564, 67565, 67568, 67664 }) |offset| {
        const bytes = try t.allocator.dupe(u8, source);
        defer t.allocator.free(bytes);
        bytes[offset] ^= 0x80;
        if (offset == 112 + 136) put(u64, bytes, offset, 138);
        if (offset == 65856 + 40) put(u16, bytes, offset, 0);
        checksums(bytes);
        if (snap.restore(&m, bytes, m.checksum)) |_| return error.ExpectedRejection else |_| {}
        try identical(&before, &m);
    }
    var v1: Machine = .{};
    try t.expectError(error.SnapshotProfile, snap.restore(&v1, source, null));
    const old = try snap.encode(t.allocator, &v1);
    defer t.allocator.free(old);
    try t.expectError(error.SnapshotProfile, snap.restore(&m, old, null));
    try identical(&before, &m);
}
test "V2 clock overflow halted stepping fault slots and complete reset" {
    var m = try machine("HALT");
    m.step();
    m.step();
    try t.expectEqual(1, m.slots);
    m.frame(0, 100);
    try t.expectEqual(20000, m.slots);
    m.slots = std.math.maxInt(u64);
    const audio = m.bus.audio;
    const irq = m.bus.irq;
    try t.expect(!m.transition(false, null));
    try t.expectEqual(error.ClockLimit, m.cpu.trap.?.kind);
    try t.expectEqualDeep(audio, m.bus.audio);
    try t.expectEqualDeep(irq, m.bus.irq);
    m.reset();
    try t.expectEqual(isa.Profile.v2, m.bus.profile);
    try t.expectEqual(0, m.slots);
    try t.expectEqual(0, m.bus.audio.generated);
    try t.expectEqual(0, m.bus.irq.depth);
    try m.validateState();
}

test "V2 debugger reverse restores audio timer IRQ and partial frame boundaries exactly" {
    var m = try machine("LDI R0, 0xd940\nLDI R1, 0xff01\nSTW R1, [R0]\nEI\nloop: B.AL loop\n");
    var recorder: @import("debug/history.zig").Recorder = .{ .allocator = t.allocator };
    defer recorder.deinit();
    try recorder.configure(32);
    for (0..26) |_| {
        const before = m;
        recorder.step(&m);
        const after = m;
        try recorder.reverse(&m);
        try identical(&before, &m);
        recorder.step(&m);
        try identical(&after, &m);
    }
    m.bus.irq.pending = 2;
    m.bus.irq.mask = 1;
    try m.bus.write16(0x42, 0xe00e); // loop instruction
    const before = m;
    recorder.step(&m);
    try t.expectEqual(1, m.irq_entries);
    try t.expectEqual(1, recorder.trace[(recorder.trace_next + 127) % 128].irq_entry.?);
    try recorder.reverse(&m);
    try identical(&before, &m);
    m.bus.irq.ie = false;
    for (0..19999 - m.slots) |_| m.step();
    const boundary = m;
    recorder.step(&m);
    try t.expectEqual(20000, m.slots);
    try t.expectEqual(800, m.bus.audio.generated);
    try recorder.reverse(&m);
    try identical(&boundary, &m);
    m.step();
    try m.validateState();
}
test "V2 debugger frame on HALT advances devices and undo restores final idle slot" {
    var m = try machine("HALT");
    var debugger: @import("debug/debugger.zig").Debugger = .{ .machine = &m, .recorder = .{ .allocator = t.allocator } };
    defer debugger.deinit();
    var output: std.Io.Writer.Allocating = .init(t.allocator);
    defer output.deinit();
    _ = try debugger.command("history 32", &output.writer);
    _ = try debugger.command("frame", &output.writer);
    try t.expectEqual(20000, m.slots);
    try t.expectEqual(1, m.cpu.retired);
    _ = try debugger.command("reverse", &output.writer);
    try t.expectEqual(19999, m.slots);
    try t.expectEqual(799, m.bus.audio.prefix);
    try m.validateState();
    _ = try debugger.command("devices", &output.writer);
    try t.expect(std.mem.indexOf(u8, output.written(), "profile=2 slots=19999") != null);
}
test "V2 maximum nesting masks DI and ninth IRQ preserve complete frames" {
    var m = try machine("EI\nDI\nB.AL 0xe000");
    try m.bus.write16(0x40, 0xe000);
    m.bus.irq.pending = 1;
    m.bus.irq.mask = 1;
    // A pending masked request stays latched across EI/DI.
    m.step();
    m.step();
    try t.expect(!m.bus.irq.ie);
    try t.expectEqual(1, m.bus.irq.pending);
    m.bus.irq.mask = 0;
    for (0..8) |_| {
        m.bus.irq.ie = true;
        m.bus.irq.pending = 1;
        m.step();
        try t.expectEqual(null, m.cpu.trap);
    }
    const saved = try snap.encodeChecked(t.allocator, &m);
    defer t.allocator.free(saved);
    var copy = m;
    try snap.restore(&copy, saved, m.checksum);
    m.bus.irq.ie = true;
    m.bus.irq.pending = 1;
    const before = m;
    m.step();
    try t.expectEqual(error.InterruptNesting, m.cpu.trap.?.kind);
    try t.expectEqualDeep(before.bus.irq, m.bus.irq);
    try t.expectEqualSlices(u8, &before.bus.bytes, &m.bus.bytes);
}
test "V2 instruction failure still ticks timer and audio and retirement cannot wrap" {
    var m = try machine(".entry 0xe000\n.word 0xffff");
    try m.bus.write16(0xd960, 1);
    m.step();
    try t.expectEqual(error.InvalidOpcode, m.cpu.trap.?.kind);
    try t.expectEqual(0, m.cpu.retired);
    try t.expectEqual(1, m.slots);
    try t.expectEqual(2, m.bus.irq.pending);
    m.reset();
    m.cpu.retired = std.math.maxInt(u64);
    m.step();
    try t.expectEqual(error.InstructionLimit, m.cpu.trap.?.kind);
    try t.expectEqual(1, m.slots);
    try t.expectEqual(std.math.maxInt(u64), m.cpu.retired);
    m.reset();
    m.slots = std.math.maxInt(u64) - 1;
    m.bus.audio.generated = m.slots / 25;
    m.bus.audio.prefix = @intCast((m.slots % 20000) / 25);
    m.bus.frame = @truncate(m.slots / 20000);
    _ = m.transition(false, null);
    try t.expectEqual(std.math.maxInt(u64), m.slots);
    const before = m;
    try t.expect(!m.transition(false, null));
    try t.expectEqualDeep(before.bus.audio, m.bus.audio);
    try t.expectEqualDeep(before.bus.irq, m.bus.irq);
    var v1: Machine = .{};
    try t.expect(!v1.transition(true, null));
    try t.expectEqual(0, v1.cpu.retired);
}

test "V2 actual clock chip and timer produce independent snapshot fixture bytes" {
    const image = try fixture("rom2_halt");
    defer t.allocator.free(image);
    for ([_]u64{ 137, 20000 }, [_][]const u8{ "snapshot2_idle137", "snapshot2_boundary20000" }) |slots, name| {
        var m: Machine = .{};
        try m.load(image);
        for (0..16) |i| for (0..3) |j| {
            m.bus.palette[i * 3 + j] = @intCast(i * 17);
        };
        try m.bus.write16(0xd902, 0x4000);
        try m.bus.write8(0xd904, 255);
        try m.bus.write8(0xd906, 1);
        try m.bus.write8(0xd940, 1);
        try m.bus.write8(0xd951, 3);
        try m.bus.write16(0xd960, 7);
        try m.bus.write8(0xd968, 1);
        for (0..slots) |_| _ = m.transition(true, null);
        // The specification fixture observes an acknowledged VBLANK latch.
        _ = try m.bus.read8(0xd805);
        const golden = try fixture(name);
        defer t.allocator.free(golden);
        const actual = try snap.encodeChecked(t.allocator, &m);
        defer t.allocator.free(actual);
        try t.expectEqualSlices(u8, golden, actual);
    }
}

test "V2 deterministic malformed MMIO transactions never partially commit" {
    var m = try machine("loop: B.AL loop");
    var seed: u32 = 0x4e313602;
    for (0..4096) |_| {
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        const address: u16 = 0xd900 + @as(u16, @truncate(seed % 128));
        const value: u16 = @truncate(seed >> 8);
        const before = m;
        const result = if (seed & 1 == 0) m.bus.write16(address, value) else m.bus.write8(address, @truncate(value));
        if (result) |_| {
            try m.validateState();
        } else |_| {
            try t.expectEqualDeep(before.bus.audio, m.bus.audio);
            try t.expectEqualDeep(before.bus.irq, m.bus.irq);
            try t.expectEqualSlices(u8, &before.bus.bytes, &m.bus.bytes);
            try t.expectEqual(before.bus.write_count, m.bus.write_count);
        }
        m.step();
        if (m.cpu.trap != null) return error.UnexpectedTrap;
    }
}
test "V2 seeded independent timer model matches partial period writes W1C reload and idle slots" {
    var m = try machine("HALT");
    var period: u32 = 0;
    var remaining: u32 = 0;
    var pending: u8 = 0;
    var reload = false;
    var seed: u32 = 0x51a70002;
    for (0..2048) |slot| {
        seed = seed *% 1664525 +% 1013904223;
        switch (seed % 8) {
            0, 1 => {
                const shift: u5 = @intCast((seed >> 8) % 4 * 8);
                const value: u8 = @truncate(seed >> 16);
                try m.bus.write8(0xd960 + @as(u16, shift / 8), value);
                period = (period & ~(@as(u32, 255) << shift)) | (@as(u32, value) << shift);
                remaining = period;
            },
            2 => {
                const value: u16 = @truncate(seed >> 16);
                try m.bus.write16(0xd960, value);
                period = (period & 0xffff0000) | value;
                remaining = period;
            },
            3 => {
                reload = seed & 0x100 != 0;
                try m.bus.write8(0xd968, @intFromBool(reload));
            },
            4 => {
                const bits: u8 = @truncate((seed >> 8) & 3);
                try m.bus.write8(0xd950, bits);
                pending &= ~bits;
            },
            5 => {
                try m.bus.write16(0xd960, 3);
                try m.bus.write16(0xd962, 0);
                period = 3;
                remaining = 3;
            },
            else => {},
        }
        _ = m.transition(true, null);
        if (remaining != 0) {
            remaining -= 1;
            if (remaining == 0) {
                pending |= 2;
                if (reload) remaining = period;
            }
        }
        if ((slot + 1) % 20000 == 0) pending |= 1;
        try t.expectEqual(period, m.bus.irq.period);
        try t.expectEqual(remaining, m.bus.irq.remaining);
        try t.expectEqual(pending, m.bus.irq.pending);
        try m.validateState();
    }
}
test "V2 snapshot allocation failures release ownership and preserve original machine" {
    const image = try fixture("rom2_halt");
    defer t.allocator.free(image);
    var m: Machine = .{};
    try m.load(image);
    const Probe = struct {
        fn check(a: std.mem.Allocator, state: *const Machine) !void {
            const bytes = try snap.encodeChecked(a, state);
            defer a.free(bytes);
        }
    };
    try t.checkAllAllocationFailures(t.allocator, Probe.check, .{&m});
    try m.validateState();
}

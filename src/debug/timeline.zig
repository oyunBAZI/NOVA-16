//! Bounded exact undo: small machine state plus pre-write RAM/VRAM bytes.
//! All device/clock/partial-PCM state is stored explicitly; immutable ROM is not
//! copied. Instruction writes must be reported through observeWrites().
const std = @import("std");
const Machine = @import("../core/machine.zig").Machine;
const Bus = @import("../core/bus.zig").Bus;
const Write = @import("../core/bus.zig").Write;
const State = struct {
    slots: u64,
    irq_entries: u64,
    cpu: @import("../core/cpu.zig").Cpu,
    profile: @import("../arch/profile.zig").Profile,
    audio: @import("../devices/audio.zig").Audio,
    irq: @import("../devices/interrupts.zig").Interrupts,
    device_address: u16,
    input: @import("../devices/input.zig").Input,
    palette: [48]u8,
    frame: u16,
    enabled: bool,
    vblank: bool,
    writes: [6]Write,
    write_count: u3,
    checksum: u32,
    entry: u16,
    rom_length: u16,
    fn capture(m: *const Machine) State {
        return .{ .slots = m.slots, .irq_entries = m.irq_entries, .cpu = m.cpu, .profile = m.bus.profile, .audio = m.bus.audio, .irq = m.bus.irq, .device_address = m.bus.device_address, .input = m.bus.input, .palette = m.bus.palette, .frame = m.bus.frame, .enabled = m.bus.enabled, .vblank = m.bus.vblank, .writes = m.bus.writes, .write_count = m.bus.write_count, .checksum = m.checksum, .entry = m.entry, .rom_length = m.rom_length };
    }
    fn restore(s: *const State, m: *Machine) void {
        m.slots = s.slots;
        m.irq_entries = s.irq_entries;
        m.cpu = s.cpu;
        m.bus.profile = s.profile;
        m.bus.audio = s.audio;
        m.bus.irq = s.irq;
        m.bus.device_address = s.device_address;
        m.bus.input = s.input;
        m.bus.palette = s.palette;
        m.bus.frame = s.frame;
        m.bus.enabled = s.enabled;
        m.bus.vblank = s.vblank;
        m.bus.writes = s.writes;
        m.bus.write_count = s.write_count;
        m.checksum = s.checksum;
        m.entry = s.entry;
        m.rom_length = s.rom_length;
    }
};
const Patch = struct { address: u16, old: u8 };
const Entry = struct { state: State, patch_start: usize, patch_count: usize = 0 };
pub const Timeline = struct {
    allocator: std.mem.Allocator,
    entries: []Entry,
    patches: []Patch,
    oldest: usize = 0,
    count: usize = 0,
    patch_next: usize = 0,
    patch_used: usize = 0,
    active: bool = false,
    discarded: usize = 0,
    deduplicate: bool = false,
    seen: [0xd800 / 8]u8 = @splat(0),
    pub const maximum_entries = 4096;
    pub const default_patches = 262144;
    pub fn init(a: std.mem.Allocator, limit: usize, patch_limit: usize) !Timeline {
        if (limit == 0 or limit > maximum_entries or patch_limit == 0 or patch_limit > default_patches) return error.HistoryLimit;
        const entries = try a.alloc(Entry, limit);
        errdefer a.free(entries);
        const patches = try a.alloc(Patch, patch_limit);
        return .{ .allocator = a, .entries = entries, .patches = patches };
    }
    pub fn deinit(self: *Timeline) void {
        self.allocator.free(self.entries);
        self.allocator.free(self.patches);
    }
    pub fn clear(self: *Timeline) void {
        self.oldest = 0;
        self.count = 0;
        self.patch_next = 0;
        self.patch_used = 0;
        self.active = false;
        self.deduplicate = false;
    }
    pub fn beginGroup(self: *Timeline) void {
        self.deduplicate = true;
        @memset(&self.seen, 0);
    }
    pub fn endGroup(self: *Timeline) void {
        self.deduplicate = false;
    }
    pub fn allocatedBytes(self: *const Timeline) usize {
        return self.entries.len * @sizeOf(Entry) + self.patches.len * @sizeOf(Patch) + self.seen.len;
    }
    fn evict(self: *Timeline) void {
        std.debug.assert(self.count > 0);
        self.patch_used -= self.entries[self.oldest].patch_count;
        self.oldest = (self.oldest + 1) % self.entries.len;
        self.count -= 1;
    }
    pub fn capture(self: *Timeline, m: *const Machine) void {
        if (self.count == self.entries.len) self.evict();
        const next = (self.oldest + self.count) % self.entries.len;
        self.entries[next] = .{ .state = State.capture(m), .patch_start = self.patch_next };
        self.count += 1;
        self.active = true;
    }
    pub fn observeWrites(self: *Timeline, writes: []const Write) void {
        if (!self.active) return;
        for (writes) |write| {
            // Palette/MMIO effects are already captured in State. ROM writes
            // are denied by the bus and never reach this journal.
            if (write.address >= 0xd800) continue;
            if (self.deduplicate) {
                const bit: u8 = @as(u8, 1) << @as(u3, @truncate(write.address));
                if (self.seen[write.address / 8] & bit != 0) continue;
                self.seen[write.address / 8] |= bit;
            }
            while (self.patch_used == self.patches.len) {
                if (self.count == 1) {
                    // An oversized embedding group cannot be represented. Drop
                    // all history rather than let reverse skip the latest action.
                    self.clear();
                    self.discarded += 1;
                    return;
                }
                self.evict();
            }
            self.patches[self.patch_next] = .{ .address = write.address, .old = write.old };
            self.patch_next = (self.patch_next + 1) % self.patches.len;
            self.patch_used += 1;
            self.entries[(self.oldest + self.count - 1) % self.entries.len].patch_count += 1;
        }
    }
    pub fn reverse(self: *Timeline, m: *Machine) !void {
        if (self.count == 0) return error.HistoryEmpty;
        const entry = &self.entries[(self.oldest + self.count - 1) % self.entries.len];
        var remaining = entry.patch_count;
        while (remaining > 0) {
            remaining -= 1;
            const patch = self.patches[(entry.patch_start + remaining) % self.patches.len];
            m.bus.bytes[patch.address] = patch.old;
        }
        self.patch_next = entry.patch_start;
        self.patch_used -= entry.patch_count;
        entry.state.restore(m);
        self.count -= 1;
        self.active = false;
    }
};

test "delta journal evicts oldest complete actions and reverses repeated bytes in order" {
    var timeline = try Timeline.init(std.testing.allocator, 3, 5);
    defer timeline.deinit();
    var m: Machine = .{};
    for (0..4) |i| {
        timeline.capture(&m);
        const old = m.bus.bytes[100];
        m.bus.bytes[100] = @intCast(i + 1);
        m.cpu.r[0] = @intCast(i + 1);
        timeline.observeWrites(&.{.{ .address = 100, .old = old, .new = @intCast(i + 1) }});
    }
    try std.testing.expectEqual(3, timeline.count);
    for (0..3) |i| {
        try timeline.reverse(&m);
        try std.testing.expectEqual(3 - i, m.bus.bytes[100]);
        try std.testing.expectEqual(3 - i, m.cpu.r[0]);
    }
    try std.testing.expectError(error.HistoryEmpty, timeline.reverse(&m));
    timeline.capture(&m);
    for (0..3) |i| {
        timeline.observeWrites(&.{.{ .address = 100, .old = m.bus.bytes[100], .new = @intCast(i + 9) }});
        m.bus.bytes[100] = @intCast(i + 9);
    }
    try timeline.reverse(&m);
    try std.testing.expectEqual(1, m.bus.bytes[100]);
}

test "delta journal pressure and oversized actions never restore an incomplete prefix" {
    var timeline = try Timeline.init(std.testing.allocator, 4, 2);
    defer timeline.deinit();
    var m: Machine = .{};
    for (0..3) |i| {
        timeline.capture(&m);
        timeline.observeWrites(&.{.{ .address = 100, .old = m.bus.bytes[100], .new = @intCast(i + 1) }});
        m.bus.bytes[100] = @intCast(i + 1);
    }
    try std.testing.expectEqual(2, timeline.count);
    try timeline.reverse(&m);
    try timeline.reverse(&m);
    try std.testing.expectEqual(1, m.bus.bytes[100]);
    timeline.capture(&m);
    timeline.observeWrites(&.{ .{ .address = 100, .old = 1, .new = 2 }, .{ .address = 100, .old = 2, .new = 3 }, .{ .address = 100, .old = 3, .new = 4 } });
    try std.testing.expectEqual(1, timeline.discarded);
    try std.testing.expectError(error.HistoryEmpty, timeline.reverse(&m));
    timeline.capture(&m);
    timeline.observeWrites(&.{.{ .address = 100, .old = 1, .new = 9 }});
    m.bus.bytes[100] = 9;
    try timeline.reverse(&m);
    try std.testing.expectEqual(1, m.bus.bytes[100]);
}

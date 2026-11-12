const std = @import("std");
const isa = @import("../arch/isa.zig");
const Input = @import("../devices/input.zig").Input;
const video = @import("../devices/video.zig");
const Fault = @import("traps.zig").Fault;
pub const Write = struct { address: u16, old: u8, new: u8 };
pub const Audio = @import("../devices/audio.zig").Audio;
pub const Interrupts = @import("../devices/interrupts.zig").Interrupts;
pub const Bus = struct {
    profile: isa.Profile = .v1,
    audio: Audio = .{},
    irq: Interrupts = .{},
    device_address: u16 = 0,
    bytes: [65536]u8 = @splat(0),
    input: Input = .{},
    palette: [48]u8 = video.default_palette,
    frame: u16 = 0,
    enabled: bool = true,
    vblank: bool = false,
    writes: [6]Write = undefined,
    write_count: u3 = 0,
    pub fn fetch(self: *Bus, a: u16) Fault!u16 {
        if (a & 1 != 0) return error.Unaligned;
        if (!isa.executable(a)) return error.ExecuteDenied;
        return self.read16(a);
    }
    pub fn validate(a: u16, write: bool) Fault!void {
        if (a >= isa.rom_base and write) return error.WriteDenied;
        if (a < isa.mmio_base or a >= isa.rom_base) return;
        if (a >= 0xd820 and a <= 0xd84f) return;
        if (a == 0xd804) return;
        if (a >= 0xd800 and a <= 0xd805 and !write) return;
        return if (write) error.WriteDenied else error.ReadDenied;
    }
    fn validateAccess(self: *const Bus, a: u16, write: bool) Fault!void {
        if (self.profile == .v2 and (Audio.permitted(a, write) or Interrupts.permitted(a, write))) return;
        return validate(a, write);
    }
    /// Debugger reads do not acknowledge read-clear device registers.
    pub fn peek(self: *const Bus, a: u16) Fault!u8 {
        try self.validateAccess(a, false);
        if (self.profile == .v2) {
            if (Audio.permitted(a, false)) return self.audio.read(a);
            if (Interrupts.permitted(a, false)) return self.irq.read(a);
        }
        return switch (a) {
            0xd800 => self.input.held,
            0xd801 => self.input.pressed,
            0xd802 => @truncate(self.frame),
            0xd803 => @truncate(self.frame >> 8),
            0xd804 => @intFromBool(self.enabled),
            0xd805 => @intFromBool(self.vblank),
            0xd820...0xd84f => self.palette[a - 0xd820],
            else => self.bytes[a],
        };
    }
    pub fn read8(self: *Bus, a: u16) Fault!u8 {
        const v = try self.peek(a);
        if (a == 0xd801) self.input.pressed = 0;
        if (a == 0xd805) self.vblank = false;
        return v;
    }
    fn validateWord(self: *const Bus, a: u16, write: bool) Fault!void {
        if (a & 1 != 0) return error.Unaligned;
        try self.validateAccess(a, write);
        try self.validateAccess(a + 1, write);
    }
    pub fn read16(self: *Bus, a: u16) Fault!u16 {
        try self.validateWord(a, false);
        return @as(u16, try self.read8(a)) | (@as(u16, try self.read8(a + 1)) << 8);
    }
    pub fn write8(self: *Bus, a: u16, v: u8) Fault!void {
        try self.validateAccess(a, true);
        if (self.profile == .v2 and a >= 0xd900 and a <= 0xd968) return self.writeDevice(a, v, 1);
        if (a == 0xd804 and v & 0xfe != 0) return error.ReservedBits;
        const old = try self.peek(a);
        switch (a) {
            0xd804 => self.enabled = v == 1,
            0xd820...0xd84f => self.palette[a - 0xd820] = v,
            else => self.bytes[a] = v,
        }
        if (self.write_count < 6) {
            self.writes[self.write_count] = .{ .address = a, .old = old, .new = v };
            self.write_count += 1;
        }
    }
    pub fn write16(self: *Bus, a: u16, v: u16) Fault!void {
        try self.validateWord(a, true);
        if (self.profile == .v2 and a >= 0xd900 and a <= 0xd968) return self.writeDevice(a, v, 2);
        // Preflight both bytes before any device side effect.
        if (a == 0xd804 and v & 0xfe != 0) return error.ReservedBits;
        try self.write8(a, @truncate(v));
        try self.write8(a + 1, @truncate(v >> 8));
    }
    fn writeDevice(self: *Bus, a: u16, value: u16, width: u2) Fault!void {
        var audio = self.audio;
        var irq = self.irq;
        var old: [2]u8 = undefined;
        for (0..width) |i| {
            const address = a + @as(u16, @intCast(i));
            self.device_address = address;
            old[i] = try self.peek(address);
            const byte: u8 = @truncate(value >> @as(u4, @intCast(i * 8)));
            if (address < 0xd950) try audio.write(address, byte) else try irq.write(address, byte);
        }
        if (a < 0xd940 and audio.voices[(a - 0xd900) / 16].step > 0x80000000) {
            self.device_address = a;
            return error.DeviceValue;
        }
        if (a >= 0xd960 and a <= 0xd963) irq.remaining = irq.period;
        self.audio = audio;
        self.irq = irq;
        for (0..width) |i| {
            if (self.write_count == 6) break;
            self.writes[self.write_count] = .{ .address = a + @as(u16, @intCast(i)), .old = old[i], .new = @truncate(value >> @as(u4, @intCast(i * 8))) };
            self.write_count += 1;
        }
    }
};
test "permissions across every region boundary" {
    var b: Bus = .{};
    for ([_]u16{ 0, 0xbfff, 0xc000, 0xd7ff }) |a| {
        try b.write8(a, 42);
        try std.testing.expectEqual(42, try b.read8(a));
    }
    for ([_]u16{ 0xd806, 0xd81f, 0xd850, 0xdfff }) |a| {
        try std.testing.expectError(error.ReadDenied, b.read8(a));
        try std.testing.expectError(error.WriteDenied, b.write8(a, 0));
    }
    for ([_]u16{ 0xe000, 0xffff }) |a| try std.testing.expectError(error.WriteDenied, b.write8(a, 0));
    for ([_]u16{ 0xbfff, 0xd7ff, 0xdfff, 0xffff }) |a| try std.testing.expectError(error.Unaligned, b.read16(a));
    for ([_]u16{ 0xc000, 0xd7fe, 0xd800, 0xdffe }) |a| try std.testing.expectError(error.ExecuteDenied, b.fetch(a));
    try b.write16(0xbffe, 0x1234);
    try std.testing.expectEqual(0x34, b.bytes[0xbffe]);
    try std.testing.expectError(error.WriteDenied, b.write16(0xd804, 0));
    try std.testing.expect(b.enabled);
    b.input.inject(17);
    try std.testing.expectEqual(17, try b.read8(0xd801));
    try std.testing.expectEqual(0, try b.read8(0xd801));
}

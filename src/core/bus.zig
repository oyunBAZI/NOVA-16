const std = @import("std");
const isa = @import("../arch/isa.zig");
const Input = @import("../devices/input.zig").Input;
const video = @import("../devices/video.zig");
const Fault = @import("traps.zig").Fault;
pub const Write = struct { address: u16, old: u8, new: u8 };
pub const Bus = struct {
    bytes: [65536]u8 = @splat(0),
    input: Input = .{},
    palette: [48]u8 = video.default_palette,
    frame: u16 = 0,
    enabled: bool = true,
    vblank: bool = false,
    writes: [2]Write = undefined,
    write_count: u2 = 0,
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
    /// Debugger reads do not acknowledge read-clear device registers.
    pub fn peek(self: *const Bus, a: u16) Fault!u8 {
        try validate(a, false);
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
    fn validateWord(a: u16, write: bool) Fault!void {
        if (a & 1 != 0) return error.Unaligned;
        try validate(a, write);
        try validate(a + 1, write);
    }
    pub fn read16(self: *Bus, a: u16) Fault!u16 {
        try validateWord(a, false);
        return @as(u16, try self.read8(a)) | (@as(u16, try self.read8(a + 1)) << 8);
    }
    pub fn write8(self: *Bus, a: u16, v: u8) Fault!void {
        try validate(a, true);
        if (a == 0xd804 and v & 0xfe != 0) return error.ReservedBits;
        const old = try self.peek(a);
        switch (a) {
            0xd804 => self.enabled = v == 1,
            0xd820...0xd84f => self.palette[a - 0xd820] = v,
            else => self.bytes[a] = v,
        }
        if (self.write_count < 2) {
            self.writes[self.write_count] = .{ .address = a, .old = old, .new = v };
            self.write_count += 1;
        }
    }
    pub fn write16(self: *Bus, a: u16, v: u16) Fault!void {
        try validateWord(a, true);
        // Preflight both bytes before any device side effect.
        if (a == 0xd804 and v & 0xfe != 0) return error.ReservedBits;
        try self.write8(a, @truncate(v));
        try self.write8(a + 1, @truncate(v >> 8));
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

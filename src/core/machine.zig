const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Bus = @import("bus.zig").Bus;
const rom = @import("../rom/format.zig");
pub const Machine = struct {
    cpu: Cpu = .{},
    bus: Bus = .{},
    checksum: u32 = 0,
    entry: u16 = 0,
    pub fn load(self: *Machine, data: []const u8) !void {
        const image = try rom.parse(data);
        self.* = .{};
        @memcpy(self.bus.bytes[0xe000..][0..image.payload.len], image.payload);
        self.entry = image.entry;
        self.checksum = image.checksum;
        self.cpu.reset(image.entry);
    }
    pub fn reset(self: *Machine) void {
        const bytes = self.bus.bytes[0xe000..].*;
        self.bus = .{};
        self.bus.bytes[0xe000..].* = bytes;
        self.cpu.reset(self.entry);
    }
    /// A host call completes one simplified frame even if HALT/BRK stops it early.
    pub fn frame(self: *Machine, input: u8, cap: u64) void {
        self.bus.input.inject(input);
        var count: u32 = 0;
        while (count < @import("../arch/isa.zig").frame_budget and self.cpu.retired < cap and !self.cpu.halted and !self.cpu.paused and self.cpu.trap == null) : (count += 1) self.step();
        self.bus.frame +%= 1;
        self.bus.vblank = true;
    }
    pub fn step(self: *Machine) void {
        self.bus.write_count = 0;
        self.cpu.step(&self.bus);
    }
};
test "raw encoded boot writes RAM and halts; reset clears writable state" {
    const a = std.testing.allocator;
    const bytes = try rom.pack(a, &.{ 0, 0x20, 0x34, 0x12, 0, 0x22, 0, 1, 0x40, 0xa0, 1, 0 }, 0);
    defer a.free(bytes);
    var m: Machine = .{};
    try m.load(bytes);
    for (0..4) |_| m.step();
    try std.testing.expect(m.cpu.halted);
    try std.testing.expectEqual(0x1234, try m.bus.read16(0x100));
    m.reset();
    try std.testing.expectEqual(0, try m.bus.read16(0x100));
    try std.testing.expectEqual(0xe000, m.cpu.pc);
}

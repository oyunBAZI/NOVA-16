const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Bus = @import("bus.zig").Bus;
const rom = @import("../rom/format.zig");
pub const Machine = struct {
    cpu: Cpu = .{},
    bus: Bus = .{},
    checksum: u32 = 0,
    entry: u16 = 0,
    rom_length: u16 = 0,
    pub fn observeCpu(self: *const Machine) Cpu {
        return self.cpu.observe();
    }
    /// Non-acknowledging inspection, including MMIO latches.
    pub fn inspect(self: *const Machine, address: u16) !u8 {
        return self.bus.peek(address);
    }
    /// Checked host patch. Validate the complete range before changing a byte.
    /// Device registers are excluded: use guest writes or explicit device APIs.
    pub fn patch(self: *Machine, address: u16, data: []const u8) !void {
        if (address >= 0xd800 or data.len > 0xd800 - @as(usize, address)) return error.WriteDenied;
        @memcpy(self.bus.bytes[address..][0..data.len], data);
        self.bus.write_count = 0;
    }
    pub fn injectInput(self: *Machine, mask: u8) void {
        self.bus.input.inject(mask);
    }
    pub fn setPaused(self: *Machine, paused: bool) !void {
        if (!paused) try self.cpu.resumeExecution() else self.cpu.paused = true;
    }
    pub fn load(self: *Machine, data: []const u8) !void {
        const image = try rom.parse(data);
        self.* = .{};
        @memcpy(self.bus.bytes[0xe000..][0..image.payload.len], image.payload);
        self.entry = image.entry;
        self.rom_length = @intCast(image.payload.len);
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

test "embedding transitions validate before commit and observations cannot mutate live state" {
    const t = std.testing;
    var m: Machine = .{};
    var observed = m.observeCpu();
    observed.r[0] = 99;
    try t.expectEqual(0, m.cpu.r[0]);
    const before = m.cpu;
    try t.expectError(error.Unaligned, m.cpu.setRegisters(@splat(42), 15, 1, 0));
    try t.expectEqualDeep(before, m.cpu);
    try t.expectError(error.InvalidStack, m.cpu.setRegisters(@splat(42), 15, 0, 65535));
    try t.expectEqualDeep(before, m.cpu);
    try m.cpu.setRegisters(@splat(42), 15, 0, 2);
    try t.expectEqual(0xbffa, m.cpu.sp);
    try m.patch(0xd7ff, &.{7});
    try t.expectError(error.WriteDenied, m.patch(0xd7ff, &.{ 8, 9 }));
    try t.expectEqual(7, try m.inspect(0xd7ff));
    try t.expectError(error.WriteDenied, m.patch(0xffff, &.{1}));
    m.injectInput(17);
    try t.expectEqual(17, try m.inspect(0xd801));
    try t.expectEqual(17, try m.inspect(0xd801));
    try m.setPaused(true);
    try m.setPaused(false);
    m.cpu.halted = true;
    try t.expectError(error.Stopped, m.setPaused(false));
    m.cpu.retired = std.math.maxInt(u64);
    m.cpu.halted = false;
    m.step();
    try t.expectEqual(error.InstructionLimit, m.cpu.trap.?.kind);
}

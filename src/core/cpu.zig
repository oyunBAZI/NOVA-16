const std = @import("std");
const isa = @import("../arch/isa.zig");
const traps = @import("traps.zig");
const Bus = @import("bus.zig").Bus;
pub const Cpu = struct {
    r: [8]u16 = @splat(0),
    pc: u16 = 0xe000,
    sp: u16 = 0xbffe,
    flags: u4 = 0,
    halted: bool = false,
    paused: bool = false,
    trap: ?traps.Trap = null,
    retired: u64 = 0,
    depth: u16 = 0,
    address: u16 = 0,
    access: traps.Access = .fetch,
    pub fn reset(self: *Cpu, entry: u16) void {
        self.* = .{ .pc = isa.rom_base + entry };
    }
    pub fn step(self: *Cpu, bus: *Bus) void {
        if (self.halted or self.paused or self.trap != null) return;
        const old = self.pc;
        self.execute(bus) catch |err| {
            self.trap = .{ .kind = err, .pc = old, .address = self.address, .access = self.access };
            self.pc = old;
            return;
        };
        self.retired += 1;
    }
    fn execute(self: *Cpu, bus: *Bus) traps.Fault!void {
        self.address = self.pc;
        self.access = .fetch;
        const w = try bus.fetch(self.pc);
        self.access = .decode;
        const i = try isa.decode(w);
        self.access = .fetch;
        if (@as(u32, self.pc) + i.len > 65535) return error.AddressOverflow;
        const next = self.pc + i.len;
        if (i.len == 4) {
            self.address = self.pc + 2;
            _ = try bus.fetch(self.pc + 2);
        }
        switch (w) {
            0 => {},
            1 => self.halted = true,
            2 => self.paused = true,
            else => return error.InvalidOpcode,
        }
        self.pc = next;
    }
};
test "reset and deterministic stepping" {
    var b: Bus = .{};
    var c: Cpu = .{};
    b.bytes[0xe002] = 1;
    c.step(&b);
    try std.testing.expectEqual(0xe002, c.pc);
    c.step(&b);
    try std.testing.expect(c.halted);
    try std.testing.expectEqual(2, c.retired);
    c.step(&b);
    try std.testing.expectEqual(2, c.retired);
    c.reset(0);
    try std.testing.expectEqual(0xbffe, c.sp);
    try std.testing.expectEqual(0, c.flags);
    for (c.r) |v| try std.testing.expectEqual(0, v);
}
test "safe invalid opcode alignment and fetch traps" {
    var b: Bus = .{};
    for ([_]u16{ 0xe001, 0xc000, 0xd800 }) |pc| {
        var c: Cpu = .{ .pc = pc };
        c.step(&b);
        try std.testing.expect(c.trap != null);
        try std.testing.expectEqual(pc, c.trap.?.pc);
    }
    b.bytes[0xe000] = 6;
    var c: Cpu = .{};
    c.step(&b);
    try std.testing.expectEqual(error.InvalidOpcode, c.trap.?.kind);
}

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
    address: i32 = 0,
    instruction: u16 = 0,
    access: traps.Access = .fetch,
    pub fn reset(self: *Cpu, entry: u16) void {
        self.* = .{ .pc = isa.rom_base + entry };
    }
    pub fn step(self: *Cpu, bus: *Bus) void {
        if (self.halted or self.paused or self.trap != null) return;
        const old = self.pc;
        self.execute(bus) catch |err| {
            self.trap = .{ .kind = err, .pc = old, .address = self.address, .access = self.access, .instruction = self.instruction };
            self.pc = old;
            return;
        };
        self.retired += 1;
    }
    fn execute(self: *Cpu, bus: *Bus) traps.Fault!void {
        self.instruction = 0;
        self.address = self.pc;
        self.access = .fetch;
        const w = try bus.fetch(self.pc);
        self.instruction = w;
        self.access = .decode;
        const i = try isa.decode(w);
        self.access = .fetch;
        if (@as(u32, self.pc) + i.len > 65535) return error.AddressOverflow;
        const next = self.pc + i.len;
        if (i.len == 4) {
            self.address = self.pc + 2;
            _ = try bus.fetch(self.pc + 2);
        }
        const imm: u16 = if (i.len == 4) try bus.fetch(self.pc + 2) else 0;
        const x = self.r[i.d];
        const y = self.r[i.s];
        var target = next;
        switch (i.major) {
            0 => switch (w) {
                0 => {},
                1 => self.halted = true,
                2 => self.paused = true,
                3 => {
                    const t = try self.peekStack(bus);
                    try self.validateTarget(t);
                    _ = try self.pop(bus);
                    target = t;
                },
                4 => try self.push(bus, self.flags),
                5 => self.flags = @truncate(try self.pop(bus)),
                else => unreachable,
            },
            1 => self.r[i.d] = y,
            2 => self.r[i.d] = imm,
            3 => self.r[i.d] = self.add(x, y),
            4 => self.r[i.d] = self.sub(x, y),
            5 => {
                self.r[i.d] = x & y;
                self.logic(x & y);
            },
            6 => {
                self.r[i.d] = x | y;
                self.logic(x | y);
            },
            7 => {
                self.r[i.d] = x ^ y;
                self.logic(x ^ y);
            },
            8 => _ = self.sub(x, y),
            9...12 => {
                const off: i6 = @bitCast(@as(u6, @truncate(w)));
                const addr: i32 = @as(i32, y) + off;
                self.access = if (i.major == 10 or i.major == 12) .write else .read;
                self.address = addr;
                if (addr < 0 or addr > 65535) return error.AddressOverflow;
                const ea: u16 = @intCast(addr);
                switch (i.major) {
                    9 => self.r[i.d] = try bus.read16(ea),
                    10 => try bus.write16(ea, x),
                    11 => self.r[i.d] = try bus.read8(ea),
                    12 => try bus.write8(ea, @truncate(x)),
                    else => unreachable,
                }
            },
            13 => if (self.condition(i.sub)) {
                const off: i8 = @bitCast(@as(u8, @truncate(w)));
                const t: i32 = @as(i32, next) + @as(i32, off) * 2;
                if (t < 0 or t > 65535) return error.AddressOverflow;
                target = @intCast(t);
                try self.validateTarget(target);
            },
            14 => {
                target = if (i.sub < 2) imm else x;
                try self.validateTarget(target);
                if (i.sub == 1 or i.sub == 3) try self.push(bus, next);
            },
            15 => switch (i.sub) {
                0...2 => {
                    const count: u4 = @truncate(y);
                    var value = x;
                    var carry = self.flags & 4;
                    for (0..count) |_| {
                        carry = if (i.sub == 0) (if (value & 0x8000 != 0) @as(u4, 4) else 0) else (if (value & 1 != 0) @as(u4, 4) else 0);
                        value = switch (i.sub) {
                            0 => value << 1,
                            1 => value >> 1,
                            else => @bitCast(@as(i16, @bitCast(value)) >> 1),
                        };
                    }
                    self.logic(value);
                    self.flags |= carry;
                    self.r[i.d] = value;
                },
                3 => {
                    self.r[i.d] = ~x;
                    self.logic(~x);
                },
                4 => {
                    const product = @as(u32, x) * y;
                    self.r[i.d] = @truncate(product);
                    self.logic(self.r[i.d]);
                    if (product > 65535) self.flags |= 4;
                },
                5 => self.logic(x & y),
                6 => self.r[i.d] = self.add(x, imm),
                7 => _ = self.sub(x, imm),
                8 => try self.push(bus, x),
                9 => self.r[i.d] = try self.pop(bus),
                10 => self.r[i.d] = self.add(x, 1),
                11 => self.r[i.d] = self.sub(x, 1),
                else => unreachable,
            },
        }
        self.pc = target;
    }
    fn validateTarget(self: *Cpu, t: u16) traps.Fault!void {
        self.address = t;
        self.access = .fetch;
        if (t & 1 != 0) return error.Unaligned;
        if (!isa.executable(t)) return error.ExecuteDenied;
    }
    fn checkStack(self: *Cpu) traps.Fault!void {
        self.address = self.sp;
        self.access = .stack;
        if (self.sp & 1 != 0 or self.sp > 0xbffe or self.sp != 0xbffe - @as(u32, self.depth) * 2) return error.InvalidStack;
    }
    fn push(self: *Cpu, b: *Bus, v: u16) traps.Fault!void {
        try self.checkStack();
        if (self.sp < 2) return error.StackOverflow;
        try b.write16(self.sp - 2, v);
        self.sp -= 2;
        self.depth += 1;
    }
    fn peekStack(self: *Cpu, b: *Bus) traps.Fault!u16 {
        try self.checkStack();
        if (self.depth == 0) return error.StackUnderflow;
        return b.read16(self.sp);
    }
    fn pop(self: *Cpu, b: *Bus) traps.Fault!u16 {
        const v = try self.peekStack(b);
        self.sp += 2;
        self.depth -= 1;
        return v;
    }
    fn logic(self: *Cpu, v: u16) void {
        self.flags = @as(u4, if (v == 0) 1 else 0) | @as(u4, if (v & 0x8000 != 0) 2 else 0);
    }
    pub fn add(self: *Cpu, x: u16, y: u16) u16 {
        const wide = @as(u32, x) + y;
        const v: u16 = @truncate(wide);
        self.logic(v);
        if (wide > 65535) self.flags |= 4;
        if ((~(x ^ y) & (x ^ v) & 0x8000) != 0) self.flags |= 8;
        return v;
    }
    pub fn sub(self: *Cpu, x: u16, y: u16) u16 {
        const v = x -% y;
        self.logic(v);
        if (x >= y) self.flags |= 4;
        if (((x ^ y) & (x ^ v) & 0x8000) != 0) self.flags |= 8;
        return v;
    }
    pub fn condition(self: *const Cpu, code: u4) bool {
        const z = self.flags & 1 != 0;
        const n = self.flags & 2 != 0;
        const c = self.flags & 4 != 0;
        const v = self.flags & 8 != 0;
        return switch (code) {
            0 => true,
            1 => z,
            2 => !z,
            3 => c,
            4 => !c,
            5 => n,
            6 => !n,
            7 => v,
            8 => !v,
            9 => c and !z,
            10 => !c or z,
            11 => n == v,
            12 => n != v,
            13 => !z and n == v,
            14 => z or n != v,
            else => false,
        };
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
test "arithmetic independent signed and unsigned oracle at critical boundaries" {
    const values = [_]u16{ 0, 1, 2, 15, 0x7ffe, 0x7fff, 0x8000, 0x8001, 0xfffe, 0xffff };
    var c: Cpu = .{};
    for (values) |x| {
        for (values) |y| {
            const signed_x: i32 = @as(i16, @bitCast(x));
            const signed_y: i32 = @as(i16, @bitCast(y));
            for (0..2) |op| {
                const result = if (op == 0) c.add(x, y) else c.sub(x, y);
                const signed = if (op == 0) signed_x + signed_y else signed_x - signed_y;
                const unsigned: i32 = if (op == 0) @as(i32, x) + y else @as(i32, x) - y;
                try std.testing.expectEqual(@as(u16, @truncate(@as(u32, @bitCast(unsigned)))), result);
                try std.testing.expectEqual(result == 0, c.flags & 1 != 0);
                try std.testing.expectEqual(result >= 0x8000, c.flags & 2 != 0);
                try std.testing.expectEqual(if (op == 0) unsigned > 65535 else unsigned >= 0, c.flags & 4 != 0);
                try std.testing.expectEqual(signed < -32768 or signed > 32767, c.flags & 8 != 0);
            }
        }
    }
}
test "all branch conditions and flag combinations" {
    var c: Cpu = .{};
    for (0..16) |f| {
        c.flags = @intCast(f);
        const z = f & 1 != 0;
        const n = f & 2 != 0;
        const carry = f & 4 != 0;
        const v = f & 8 != 0;
        const expected = [_]bool{ true, z, !z, carry, !carry, n, !n, v, !v, carry and !z, !carry or z, n == v, n != v, !z and n == v, z or n != v };
        for (expected, 0..) |e, k| try std.testing.expectEqual(e, c.condition(@intCast(k)));
    }
}
test "nested CALL RET and invalid call atomicity" {
    var b: Bus = .{};
    var c: Cpu = .{};
    const words = [_]u16{ 0xe100, 0xe006, 1, 0xe100, 0xe00c, 3, 0xfA00, 3 };
    for (words, 0..) |w, k| {
        b.bytes[0xe000 + k * 2] = @truncate(w);
        b.bytes[0xe001 + k * 2] = @truncate(w >> 8);
    }
    for (0..7) |_| c.step(&b);
    try std.testing.expect(c.halted);
    try std.testing.expectEqual(1, c.r[0]);
    try std.testing.expectEqual(0xbffe, c.sp);
    c.reset(0);
    b.bytes[0xe002] = 1;
    b.bytes[0xe003] = 0xc0;
    c.step(&b);
    try std.testing.expectEqual(error.Unaligned, c.trap.?.kind);
    try std.testing.expectEqual(0, c.depth);
    c.reset(6);
    b.bytes[0xe006] = 3;
    b.bytes[0xe007] = 0;
    c.step(&b);
    try std.testing.expectEqual(error.StackUnderflow, c.trap.?.kind);
}
test "shift zero preserves carry and count 15 extracts final bit" {
    var b: Bus = .{};
    for (0..3) |op| {
        for ([_]u16{ 0, 1, 0x8000, 0xffff }) |x| {
            for ([_]u16{ 0, 1, 15 }) |count| {
                var c: Cpu = .{};
                c.r[0] = x;
                c.r[1] = count;
                c.flags = 12;
                try b.write16(0, @as(u16, 0xf004) + @as(u16, @intCast(op)) * 256);
                c.pc = 0;
                c.step(&b);
                const shift: u4 = @intCast(count);
                const expected: u16 = switch (op) {
                    0 => x << shift,
                    1 => x >> shift,
                    else => @bitCast(@as(i16, @bitCast(x)) >> shift),
                };
                try std.testing.expectEqual(expected, c.r[0]);
                try std.testing.expect(c.flags & 8 == 0);
                if (count == 0) try std.testing.expect(c.flags & 4 != 0);
            }
        }
    }
}

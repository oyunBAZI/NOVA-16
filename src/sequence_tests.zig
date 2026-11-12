//! Stateful differential execution. The reference consumes generated operations,
//! not decoded emulator instructions, and uses wide signed arithmetic.
const std = @import("std");
const Machine = @import("core/machine.zig").Machine;
const Reference = struct {
    r: [8]u16 = @splat(0),
    flags: u4 = 0,
    depth: usize = 0,
    stack: [128]u16 = undefined,
    ram: [32]u8 = @splat(0),
    fn logic(self: *Reference, v: u16, carry: bool, overflow: bool) void {
        self.flags = 0;
        if (v == 0) self.flags += 1;
        if (v >= 32768) self.flags += 2;
        if (carry) self.flags += 4;
        if (overflow) self.flags += 8;
    }
    fn arithmetic(self: *Reference, x: u16, y: u16, subtract: bool) u16 {
        const sx: i64 = if (x >= 32768) @as(i64, x) - 65536 else x;
        const sy: i64 = if (y >= 32768) @as(i64, y) - 65536 else y;
        const wide: i64 = if (subtract) @as(i64, x) - y else @as(i64, x) + y;
        const signed = if (subtract) sx - sy else sx + sy;
        const v: u16 = @intCast(@mod(wide, 65536));
        self.logic(v, if (subtract) wide >= 0 else wide >= 65536, signed < -32768 or signed > 32767);
        return v;
    }
    fn condition(self: *Reference, c: usize) bool {
        const z = self.flags & 1 != 0;
        const n = self.flags & 2 != 0;
        const carry = self.flags & 4 != 0;
        const v = self.flags & 8 != 0;
        const table = [_]bool{ true, z, !z, carry, !carry, n, !n, v, !v, carry and !z, !carry or z, n == v, n != v, !z and n == v, z or n != v };
        return table[c];
    }
};
test "stateful differential ALU memory stack and control streams across 32 seeds" {
    for (0..32) |seed| {
        var random = std.Random.DefaultPrng.init(seed);
        const rng = random.random();
        var m: Machine = .{};
        var ref: Reference = .{};
        m.cpu.r[7] = 0x1000;
        ref.r[7] = 0x1000;
        for (0..300) |step| {
            const d = rng.intRangeAtMost(u16, 0, 6);
            const s = rng.intRangeAtMost(u16, 0, 6);
            const x = ref.r[d];
            const y = ref.r[s];
            const imm = rng.int(u16);
            const pc = m.cpu.pc;
            var word: u16 = 0;
            var len: u16 = 2;
            var next: u16 = pc + 2;
            switch (rng.intRangeAtMost(u8, 0, 19)) {
                0 => {
                    word = 0x1000 | (d << 9) | (s << 6);
                    ref.r[d] = y;
                },
                1 => {
                    word = 0x2000 | (d << 9);
                    len = 4;
                    next = pc + 4;
                    ref.r[d] = imm;
                },
                2...7 => |op| {
                    const major: u16 = op + 1;
                    word = (major << 12) | (d << 9) | (s << 6);
                    switch (major) {
                        3 => ref.r[d] = ref.arithmetic(x, y, false),
                        4 => ref.r[d] = ref.arithmetic(x, y, true),
                        5 => {
                            ref.r[d] = x & y;
                            ref.logic(ref.r[d], false, false);
                        },
                        6 => {
                            ref.r[d] = x | y;
                            ref.logic(ref.r[d], false, false);
                        },
                        7 => {
                            ref.r[d] = x ^ y;
                            ref.logic(ref.r[d], false, false);
                        },
                        8 => _ = ref.arithmetic(x, y, true),
                        else => unreachable,
                    }
                },
                8...10 => |sub| {
                    const which: u16 = sub - 8;
                    word = 0xf000 | (which << 8) | (d << 5) | (s << 2);
                    const count: u4 = @truncate(y);
                    const carry = if (count == 0) ref.flags & 4 != 0 else if (which == 0) (@as(u32, x) & (@as(u32, 1) << (@as(u5, 16) - count))) != 0 else (@as(u32, x) & (@as(u32, 1) << (@as(u5, count) - 1))) != 0;
                    ref.r[d] = if (which == 0) @truncate(@as(u32, x) << count) else if (which == 1) x >> count else blk: {
                        const signed: i64 = if (x >= 32768) @as(i64, x) - 65536 else x;
                        break :blk @intCast(@mod(@divFloor(signed, @as(i64, 1) << count), 65536));
                    };
                    ref.logic(ref.r[d], carry, false);
                },
                11 => {
                    word = 0xf300 | (d << 5);
                    ref.r[d] = 65535 - x;
                    ref.logic(ref.r[d], false, false);
                },
                12 => {
                    word = 0xf400 | (d << 5) | (s << 2);
                    const product = @as(u64, x) * y;
                    ref.r[d] = @intCast(product % 65536);
                    ref.logic(ref.r[d], product > 65535, false);
                },
                13 => {
                    word = 0xf500 | (d << 5) | (s << 2);
                    ref.logic(x & y, false, false);
                },
                14 => {
                    const subtract = rng.boolean();
                    word = (if (subtract) @as(u16, 0xf700) else 0xf600) | (d << 5);
                    len = 4;
                    next = pc + 4;
                    const v = ref.arithmetic(x, imm, subtract);
                    if (!subtract) ref.r[d] = v;
                },
                15 => {
                    const major = rng.intRangeAtMost(u16, 9, 12);
                    const offset = rng.intRangeAtMost(u16, 0, 15) * 2;
                    word = (major << 12) | (d << 9) | (7 << 6) | offset;
                    switch (major) {
                        9 => ref.r[d] = @as(u16, ref.ram[offset]) + @as(u16, ref.ram[offset + 1]) * 256,
                        10 => {
                            ref.ram[offset] = @truncate(x);
                            ref.ram[offset + 1] = @truncate(x >> 8);
                        },
                        11 => ref.r[d] = ref.ram[offset],
                        12 => ref.ram[offset] = @truncate(x),
                        else => unreachable,
                    }
                },
                16 => {
                    if (ref.depth == 0 or (ref.depth < ref.stack.len and rng.boolean())) {
                        word = 0xf800 | (d << 5);
                        ref.stack[ref.depth] = x;
                        ref.depth += 1;
                    } else {
                        word = 0xf900 | (d << 5);
                        ref.depth -= 1;
                        ref.r[d] = ref.stack[ref.depth];
                    }
                },
                17 => {
                    const decrement = rng.boolean();
                    word = (if (decrement) @as(u16, 0xfb00) else 0xfa00) | (d << 5);
                    ref.r[d] = ref.arithmetic(x, 1, decrement);
                },
                18 => {
                    const cond = rng.intRangeAtMost(u16, 0, 14);
                    word = 0xd000 | (cond << 8) | 1;
                    if (ref.condition(cond)) next = pc + 4;
                },
                19 => {
                    word = 0xe000;
                    len = 4;
                    next = pc + 6;
                },
                else => unreachable,
            }
            std.mem.writeInt(u16, m.bus.bytes[pc..][0..2], word, .little);
            if (len == 4) std.mem.writeInt(u16, m.bus.bytes[pc + 2 ..][0..2], if (word == 0xe000) next else imm, .little);
            m.step();
            if (m.cpu.trap != null) std.debug.print("seed={d} step={d} pc={x} word={x}\n", .{ seed, step, pc, word });
            try std.testing.expect(m.cpu.trap == null);
            try std.testing.expectEqual(next, m.cpu.pc);
            try std.testing.expectEqualSlices(u16, &ref.r, &m.cpu.r);
            try std.testing.expectEqual(ref.flags, m.cpu.flags);
            try std.testing.expectEqual(0xbffe - ref.depth * 2, m.cpu.sp);
            try std.testing.expectEqual(step + 1, m.cpu.retired);
            try std.testing.expectEqualSlices(u8, &ref.ram, m.bus.bytes[0x1000..0x1020]);
            for (0..ref.depth) |k| try std.testing.expectEqual(ref.stack[k], try m.bus.read16(@intCast(0xbffc - k * 2)));
        }
    }
}
test "invalid public stack depth traps safely without arithmetic panic" {
    var m: Machine = .{};
    m.cpu.depth = 65535;
    m.bus.bytes[0xe000] = 3;
    m.step();
    try std.testing.expectEqual(error.InvalidStack, m.cpu.trap.?.kind);
}
test "self-modifying RAM instruction is fetched after guest store" {
    var m: Machine = .{};
    m.cpu.pc = 0;
    m.cpu.r[0] = 6;
    m.cpu.r[1] = 1;
    try m.bus.write16(0, 0xa200); // STW R1,[R0]
    try m.bus.write16(2, 0xe000);
    try m.bus.write16(4, 6);
    m.step();
    m.step();
    m.step();
    try std.testing.expect(m.cpu.halted);
    try std.testing.expectEqual(3, m.cpu.retired);
}

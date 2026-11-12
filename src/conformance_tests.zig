//! Independent ISA and fault conformance checks. References deliberately avoid
//! the implementation's decode/flag helpers, so shared mistakes do not pass.
const std = @import("std");
const Cpu = @import("core/cpu.zig").Cpu;
const Bus = @import("core/bus.zig").Bus;
const Machine = @import("core/machine.zig").Machine;
const isa = @import("arch/isa.zig");
const rom = @import("rom/format.zig");
const assembler = @import("asm/assembler.zig");
const Debugger = @import("debug/debugger.zig").Debugger;
const E = std.testing.expectEqual;
const expect = std.testing.expect;

fn writeInstruction(b: *Bus, w: u16, imm: u16) void {
    std.mem.writeInt(u16, b.bytes[0xe000..0xe002], w, .little);
    std.mem.writeInt(u16, b.bytes[0xe002..0xe004], imm, .little);
}
fn referenceFlags(result: u16, carry: bool, overflow: bool) u4 {
    var bits: u4 = 0;
    if (result == 0) bits += 1;
    if (result >= 32768) bits += 2;
    if (carry) bits += 4;
    if (overflow) bits += 8;
    return bits;
}
fn referenceArithmetic(x: u16, y: u16, subtract: bool) struct { value: u16, flags: u4 } {
    const wide: i64 = if (subtract) @as(i64, x) - y else @as(i64, x) + y;
    const signed_x: i64 = if (x >= 32768) @as(i64, x) - 65536 else x;
    const signed_y: i64 = if (y >= 32768) @as(i64, y) - 65536 else y;
    const signed = if (subtract) signed_x - signed_y else signed_x + signed_y;
    const value: u16 = @intCast(@mod(wide, 65536));
    return .{ .value = value, .flags = referenceFlags(value, if (subtract) wide >= 0 else wide >= 65536, signed < -32768 or signed > 32767) };
}

test "decoder reference mask matrix covers all 65536 first words" {
    for (0..65536) |raw| {
        const w: u16 = @intCast(raw);
        const major = raw / 4096;
        const sub = (raw / 256) % 16;
        const valid = switch (major) {
            0 => raw <= 5,
            1, 3...8 => raw % 64 == 0,
            2 => raw % 512 == 0,
            9...12 => true,
            13 => sub != 15,
            14 => sub < 4 and (if (sub < 2) raw % 256 == 0 else raw % 32 == 0),
            15 => sub < 12 and raw % 4 == 0 and (if (sub == 3 or sub >= 6) raw % 32 == 0 else true),
            else => unreachable,
        };
        if (valid) {
            const decoded = try isa.decode(w);
            const expected_length: u3 = if (major == 2 or (major == 14 and sub < 2) or (major == 15 and (sub == 6 or sub == 7))) 4 else 2;
            try E(expected_length, decoded.len);
        } else try std.testing.expectError(error.InvalidOpcode, isa.decode(w));
    }
}

test "every malformed opcode traps in the CPU rather than only decoder" {
    var b: Bus = .{};
    for (0..65536) |raw| {
        const w: u16 = @intCast(raw);
        _ = isa.decode(w) catch {
            writeInstruction(&b, w, 0);
            var c: Cpu = .{};
            c.step(&b);
            try E(error.InvalidOpcode, c.trap.?.kind);
            try E(0xe000, c.pc);
            try E(0, c.retired);
            continue;
        };
    }
}

test "ALU instructions all registers flags edge operands and independent oracle" {
    const edges = [_]u16{ 0, 1, 2, 15, 16, 0x7fff, 0x8000, 0x8001, 0xfffe, 0xffff };
    var bus: Bus = .{};
    for (1..9) |major| {
        if (major == 2) continue;
        for (0..8) |rd| {
            for (0..8) |rs| {
                for (edges) |left| {
                    for (edges) |right| {
                        var c: Cpu = .{};
                        c.flags = 15;
                        c.r[rd] = left;
                        c.r[rs] = right;
                        const x = c.r[rd];
                        const y = c.r[rs];
                        const word: u16 = @intCast(major * 4096 + rd * 512 + rs * 64);
                        writeInstruction(&bus, word, 0);
                        c.step(&bus);
                        try expect(c.trap == null);
                        var expected = x;
                        var flags: u4 = 15;
                        switch (major) {
                            1 => expected = y,
                            3, 4, 8 => {
                                const ref = referenceArithmetic(x, y, major != 3);
                                flags = ref.flags;
                                if (major != 8) expected = ref.value;
                            },
                            5 => {
                                expected = x & y;
                                flags = referenceFlags(expected, false, false);
                            },
                            6 => {
                                expected = x | y;
                                flags = referenceFlags(expected, false, false);
                            },
                            7 => {
                                expected = x ^ y;
                                flags = referenceFlags(expected, false, false);
                            },
                            else => unreachable,
                        }
                        try E(expected, c.r[rd]);
                        try E(flags, c.flags);
                        try E(0xe002, c.pc);
                        try E(1, c.retired);
                        for (0..8) |reg| {
                            if (reg != rd) try E(if (reg == rs) y else @as(u16, 0), c.r[reg]);
                        }
                    }
                }
            }
        }
    }
}

test "extended ALU execution and immediate sequencing" {
    const values = [_]u16{ 0, 1, 15, 16, 0x7fff, 0x8000, 0xffff };
    var bus: Bus = .{};
    for (0..8) |sub| {
        for (values) |x| {
            for (values) |y| {
                var c: Cpu = .{};
                c.r[2] = x;
                c.r[3] = y;
                c.flags = 15;
                const unary = sub == 3 or sub == 6 or sub == 7;
                writeInstruction(&bus, @intCast(0xf000 + sub * 256 + 2 * 32 + (if (unary) @as(usize, 0) else 3 * 4)), y);
                c.step(&bus);
                try expect(c.trap == null);
                var result = x;
                var expected = x;
                var flags: u4 = 0;
                switch (sub) {
                    0...2 => {
                        const count: u4 = @truncate(y);
                        const wide: u64 = x;
                        result = if (sub == 0) @truncate(wide << count) else if (sub == 1) @intCast(wide >> count) else blk: {
                            const sx: i64 = if (x >= 32768) @as(i64, x) - 65536 else x;
                            const shifted = @divFloor(sx, @as(i64, 1) << count);
                            break :blk @intCast(@mod(shifted, 65536));
                        };
                        const carry = if (count == 0) true else if (sub == 0) (wide & (@as(u64, 1) << (@as(u6, 16) - count))) != 0 else (wide & (@as(u64, 1) << (@as(u6, count) - 1))) != 0;
                        flags = referenceFlags(result, carry, false);
                        expected = result;
                    },
                    3 => {
                        expected = 65535 - x;
                        flags = referenceFlags(expected, false, false);
                    },
                    4 => {
                        const product = @as(u64, x) * y;
                        expected = @intCast(product % 65536);
                        flags = referenceFlags(expected, product > 65535, false);
                    },
                    5 => flags = referenceFlags(x & y, false, false),
                    6, 7 => {
                        const ref = referenceArithmetic(x, y, sub == 7);
                        flags = ref.flags;
                        if (sub == 6) expected = ref.value;
                    },
                    else => unreachable,
                }
                try E(expected, c.r[2]);
                try E(flags, c.flags);
                try E(if (sub == 6 or sub == 7) @as(u16, 0xe004) else 0xe002, c.pc);
            }
        }
    }
    for ([_]u16{ 0, 1, 0x7fff, 0x8000, 0xffff }) |x| {
        for ([_]u16{ 0xfa00, 0xfb00 }) |word| {
            var c: Cpu = .{};
            c.r[0] = x;
            writeInstruction(&bus, word, 0);
            c.step(&bus);
            const ref = referenceArithmetic(x, 1, word == 0xfb00);
            try E(ref.value, c.r[0]);
            try E(ref.flags, c.flags);
        }
    }
}

test "all conditions actually transfer PC with positive and negative offsets" {
    var b: Bus = .{};
    for (0..15) |cond| {
        for (0..16) |flags| {
            for ([_]i8{ -128, -1, 0, 1, 127 }) |offset| {
                var c: Cpu = .{};
                c.flags = @intCast(flags);
                const taken = c.condition(@intCast(cond));
                const w: u16 = 0xd000 | (@as(u16, @intCast(cond)) << 8) | @as(u8, @bitCast(offset));
                writeInstruction(&b, w, 0);
                c.step(&b);
                const dest: u16 = @intCast(if (taken) @as(i32, 0xe002) + @as(i32, offset) * 2 else 0xe002);
                if (taken and !isa.executable(dest)) {
                    try E(error.ExecuteDenied, c.trap.?.kind);
                    try E(0xe000, c.pc);
                } else {
                    try expect(c.trap == null);
                    try E(dest, c.pc);
                }
            }
        }
    }
}

test "load store register fields byte extension negative offsets and flags unchanged" {
    var b: Bus = .{};
    for ([_]u16{ 0x9000, 0xa000, 0xb000, 0xc000 }) |base| {
        for ([_]i6{ -32, -2, 0, 2, 30 }) |offset| {
            var c: Cpu = .{};
            c.flags = 15;
            c.r[2] = 0x1120;
            c.r[3] = 0xabcd;
            const addr: u16 = @intCast(@as(i32, 0x1120) + offset);
            b.bytes[addr] = 0x76;
            b.bytes[addr + 1] = 0x98;
            writeInstruction(&b, base | (3 << 9) | (2 << 6) | @as(u6, @bitCast(offset)), 0);
            c.step(&b);
            try expect(c.trap == null);
            try E(15, c.flags);
            switch (base) {
                0x9000 => try E(0x9876, c.r[3]),
                0xb000 => try E(0x76, c.r[3]),
                0xa000 => try E(0xabcd, try b.read16(addr)),
                0xc000 => {
                    try E(0xcd, b.bytes[addr]);
                    try E(0x98, b.bytes[addr + 1]);
                },
                else => unreachable,
            }
        }
    }
    for ([_]u16{ 0, 65535 }) |address| {
        var c: Cpu = .{};
        c.r[1] = address;
        writeInstruction(&b, if (address == 0) 0xb03f else 0xb001, 0); // replaced base field below
        const off: u16 = if (address == 0) 63 else 1;
        writeInstruction(&b, 0xb040 | off, 0);
        c.step(&b);
        try E(error.AddressOverflow, c.trap.?.kind);
        try E(0xe000, c.trap.?.pc);
    }
}

test "stack full depth underflow invalid SP and RET validation are atomic" {
    var b: Bus = .{};
    var c: Cpu = .{};
    writeInstruction(&b, 0xf800, 0);
    for (0..24575) |_| {
        c.pc = 0xe000;
        c.step(&b);
        try expect(c.trap == null);
    }
    try E(0, c.sp);
    try E(24575, c.depth);
    c.pc = 0xe000;
    c.step(&b);
    try E(error.StackOverflow, c.trap.?.kind);
    c = .{};
    c.sp = 1;
    c.step(&b);
    try E(error.InvalidStack, c.trap.?.kind);
    c = .{};
    writeInstruction(&b, 0xf900, 0);
    c.step(&b);
    try E(error.StackUnderflow, c.trap.?.kind);
    c = .{};
    c.r[0] = 0xc000;
    writeInstruction(&b, 0xf800, 0);
    c.step(&b);
    c.pc = 0xe000;
    writeInstruction(&b, 3, 0);
    c.step(&b);
    try E(error.ExecuteDenied, c.trap.?.kind);
    try E(1, c.depth);
    try E(0xbffc, c.sp);
}

test "PUSHF POPF register CALLR JMPR and full decode return PC" {
    var b: Bus = .{};
    var c: Cpu = .{};
    c.flags = 15;
    writeInstruction(&b, 4, 0);
    c.step(&b);
    try E(15, try b.read16(0xbffc));
    c.flags = 0;
    c.pc = 0xe000;
    writeInstruction(&b, 5, 0);
    c.step(&b);
    try E(15, c.flags);
    try E(0, c.depth);
    c = .{};
    c.r[4] = 0x100;
    writeInstruction(&b, 0xe380, 0);
    c.step(&b);
    try E(0x100, c.pc);
    try E(0xe002, try b.read16(0xbffc));
    try b.write16(0x100, 3);
    c.step(&b);
    try E(0xe002, c.pc);
    try E(0, c.depth);
    c = .{};
    c.r[7] = 0x200;
    writeInstruction(&b, 0xe2e0, 0);
    c.step(&b);
    try E(0x200, c.pc);
    c = .{};
    writeInstruction(&b, 0xe100, 0x100);
    c.step(&b);
    try E(0xe004, try b.read16(0xbffc));
    c = .{};
    c.r[4] = 0xd800;
    writeInstruction(&b, 0xe380, 0);
    c.step(&b);
    try E(0, c.depth);
    try E(error.ExecuteDenied, c.trap.?.kind);
}

test "MMIO exhaustive address whitelist and word transaction preflight" {
    var b: Bus = .{};
    for (0xd800..0xe000) |addr| {
        const a: u16 = @intCast(addr);
        const read = addr <= 0xd805 or (addr >= 0xd820 and addr <= 0xd84f);
        const write = addr == 0xd804 or (addr >= 0xd820 and addr <= 0xd84f);
        if (read) _ = try b.read8(a) else try std.testing.expectError(error.ReadDenied, b.read8(a));
        if (write) try b.write8(a, 0) else try std.testing.expectError(error.WriteDenied, b.write8(a, 0));
    }
    b.input.inject(3);
    try E(0x0303, try b.read16(0xd800));
    try E(0, b.input.pressed);
    b.enabled = true;
    try std.testing.expectError(error.WriteDenied, b.write16(0xd804, 0));
    try expect(b.enabled);
    try std.testing.expectError(error.ReservedBits, b.write8(0xd804, 2));
    try expect(b.enabled);
    try b.write16(0xd84e, 0x1234);
    try E(0x34, b.palette[46]);
    try E(0x12, b.palette[47]);
    try std.testing.expectError(error.WriteDenied, b.write16(0xd850, 0));
}

test "watchpoints include both word bytes and palette MMIO; inspection is nondestructive" {
    const a = std.testing.allocator;
    var diag: assembler.Diagnostic = .{};
    const r = try assembler.assemble(a, "LDI R0, 0xd820\nLDI R1, 0x1234\nSTW R1, [R0]\nHALT", &diag);
    defer r.deinit();
    var m: Machine = .{};
    try m.load(r.image);
    var d: Debugger = .{ .machine = &m };
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    _ = try d.command("watch 0xd821", &out.writer);
    _ = try d.command("continue", &out.writer);
    try E(3, m.cpu.retired);
    try expect(std.mem.indexOf(u8, out.written(), "watch d821:") != null);
    m.bus.input.inject(0x80);
    m.bus.vblank = true;
    _ = try d.command("mem 0xd800 6", &out.writer);
    try E(128, m.bus.input.pressed);
    try expect(m.bus.vblank);
    _ = try d.command("unwatch 0xd821", &out.writer);
    _ = try d.command("continue", &out.writer);
    try expect(m.cpu.halted);
}

test "bounded randomized malformed ROM and assembler inputs never panic or leak" {
    const a = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0x4e313652);
    const random = prng.random();
    var bytes: [256]u8 = undefined;
    for (0..2000) |_| {
        random.bytes(&bytes);
        const len = random.intRangeAtMost(usize, 0, bytes.len);
        _ = rom.parse(bytes[0..len]) catch {};
        // ASCII is intentionally not sanitized into valid tokens.
        for (bytes[0..len]) |*c| c.* = 32 + c.* % 96;
        var diagnostic: assembler.Diagnostic = .{};
        if (assembler.assemble(a, bytes[0..len], &diagnostic)) |r| r.deinit() else |_| {}
    }
    const valid = try rom.pack(a, &.{ 0, 0, 1, 0 }, 0);
    defer a.free(valid);
    var trailing: [37]u8 = undefined;
    @memcpy(trailing[0..36], valid);
    trailing[36] = 0;
    try std.testing.expectError(error.BadSize, rom.parse(&trailing));
    try std.testing.expectError(error.BadLength, rom.pack(a, &.{}, 0));
    try std.testing.expectError(error.BadEntry, rom.pack(a, &.{ 0, 0 }, 1));
}

test "arbitrary legal and illegal guest words run with a hard instruction bound" {
    var b: Bus = .{};
    var random = std.Random.DefaultPrng.init(16);
    for (0..1000) |_| {
        random.random().bytes(b.bytes[0xe000..]);
        var c: Cpu = .{};
        for (0..100) |_| {
            c.step(&b);
            if (c.halted or c.paused or c.trap != null) break;
        }
        try expect(c.retired <= 100);
    }
}

test "frame rollover hard cap BRK HALT and failed load leave deterministic state" {
    const a = std.testing.allocator;
    const data = try rom.pack(a, &.{ 0xff, 0xd0 }, 0);
    defer a.free(data);
    var m: Machine = .{};
    try m.load(data);
    m.bus.frame = 65535;
    m.frame(0, 7);
    try E(7, m.cpu.retired);
    try E(0, m.bus.frame);
    try expect(m.bus.vblank);
    try std.testing.expectError(error.BadMagic, m.load(&(@as([36]u8, @splat(0)))));
    try E(7, m.cpu.retired);
    m.reset();
    m.bus.bytes[0xe000] = 2;
    m.bus.bytes[0xe001] = 0;
    m.frame(0, 100);
    try E(1, m.cpu.retired);
    try E(1, m.bus.frame);
    try expect(m.cpu.paused);
    try E(0xe002, m.cpu.pc);
    m.reset();
    m.bus.bytes[0xe000] = 1;
    m.bus.bytes[0xe001] = 0;
    m.frame(0, 100);
    try E(1, m.cpu.retired);
    try expect(m.cpu.halted);
}
test "instruction crossing executable regions and PC overflow trap before retirement" {
    var b: Bus = .{};
    for ([_]u16{ 0xbffe, 0xfffe, 0xfffc }) |pc| {
        var c: Cpu = .{ .pc = pc };
        std.mem.writeInt(u16, b.bytes[pc..][0..2], 0x2000, .little);
        c.step(&b);
        try expect(c.trap != null);
        try E(0, c.retired);
        try E(pc, c.pc);
        try E(if (pc == 0xbffe) error.ExecuteDenied else error.AddressOverflow, c.trap.?.kind);
    }
    var c: Cpu = .{};
    c.r[1] = 0;
    writeInstruction(&b, 0xb07f, 0);
    c.step(&b);
    try E(-1, c.trap.?.address);
    try E(0xb07f, c.trap.?.instruction);
}

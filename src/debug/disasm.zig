const std = @import("std");
const isa = @import("../arch/isa.zig");
pub fn instruction(wr: *std.Io.Writer, w: u16, imm: ?u16, pc: u16) !u3 {
    return instructionProfile(wr, w, imm, pc, .v1);
}
pub fn instructionProfile(wr: *std.Io.Writer, w: u16, imm: ?u16, pc: u16, profile: isa.Profile) !u3 {
    const i = isa.decodeProfile(w, profile) catch {
        try wr.print(".word 0x{x:0>4}", .{w});
        return 2;
    };
    if (i.len == 4 and imm == null) {
        try wr.print(".word 0x{x:0>4}", .{w});
        return 2;
    }
    switch (i.major) {
        0 => try wr.writeAll(if (w < 6) isa.system_names[w] else isa.v2_system_names[w - 6]),
        1, 3...8 => try wr.print("{s} R{d}, R{d}", .{ isa.major_names[i.major], i.d, i.s }),
        2 => try wr.print("LDI R{d}, 0x{x:0>4}", .{ i.d, imm.? }),
        9...12 => {
            const off: i6 = @bitCast(@as(u6, @truncate(w)));
            try wr.print("{s} R{d}, [R{d} + {d}]", .{ isa.major_names[i.major], i.d, i.s, off });
        },
        13 => {
            const off: i8 = @bitCast(@as(u8, @truncate(w)));
            const dest = @as(i32, pc) + 2 + @as(i32, off) * 2;
            if (dest < 0 or dest > 65535 or !isa.executable(@intCast(dest))) {
                try wr.print(".word 0x{x:0>4}", .{w});
                return 2;
            }
            try wr.print("B.{s} 0x{x:0>4}", .{ isa.condition_names[i.sub], @as(u16, @intCast(dest)) });
        },
        14 => {
            if (i.sub < 2) {
                if (!isa.executable(imm.?)) {
                    try wr.print(".word 0x{x:0>4}, 0x{x:0>4}", .{ w, imm.? });
                    return 4;
                }
                try wr.print("{s} 0x{x:0>4}", .{ isa.control_names[i.sub], imm.? });
            } else try wr.print("{s} R{d}", .{ isa.control_names[i.sub], i.d });
        },
        15 => {
            if (i.sub == 6 or i.sub == 7) try wr.print("{s} R{d}, 0x{x:0>4}", .{ isa.ext_names[i.sub], i.d, imm.? }) else if (i.sub == 3 or i.sub >= 8) try wr.print("{s} R{d}", .{ isa.ext_names[i.sub], i.d }) else try wr.print("{s} R{d}, R{d}", .{ isa.ext_names[i.sub], i.d, i.s });
        },
    }
    return i.len;
}
test "every legal word disassembles and assembles losslessly" {
    const assembler = @import("../asm/assembler.zig");
    const a = std.testing.allocator;
    var buffer: [256]u8 = undefined;
    for (0..65536) |raw| {
        const w: u16 = @intCast(raw);
        const i = isa.decode(w) catch continue;
        var out = std.Io.Writer.fixed(&buffer);
        _ = try instruction(&out, w, 0xe000, 0xe000);
        try out.writeAll("\n.entry 0xe000\n");
        var d: assembler.Diagnostic = .{};
        const r = assembler.assemble(a, out.buffered(), &d) catch |err| {
            std.debug.print("{s} {s}\n", .{ out.buffered(), @errorName(err) });
            return err;
        };
        defer r.deinit();
        try std.testing.expectEqual(w, std.mem.readInt(u16, r.image[32..34], .little));
        if (i.len == 4) try std.testing.expectEqual(0xe000, std.mem.readInt(u16, r.image[34..36], .little));
    }
}

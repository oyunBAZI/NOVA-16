const std = @import("std");
pub const ram_end = 0xc000;
pub const vram_base = 0xc000;
pub const mmio_base = 0xd800;
pub const rom_base = 0xe000;
pub const rom_size = 8192;
pub const stack_top = 0xbffe;
pub const stack_capacity = stack_top / 2;
pub const frame_budget = 20_000;
pub const system_names = [_][]const u8{ "NOP", "HALT", "BRK", "RET", "PUSHF", "POPF" };
pub const major_names = [_][]const u8{ "", "MOV", "LDI", "ADD", "SUB", "AND", "OR", "XOR", "CMP", "LDW", "STW", "LDB", "STB" };
pub const ext_names = [_][]const u8{ "SHL", "SHR", "SAR", "NOT", "MUL", "TEST", "ADDI", "CMPI", "PUSH", "POP", "INC", "DEC" };
pub const control_names = [_][]const u8{ "JMP", "CALL", "JMPR", "CALLR" };
pub const condition_names = [_][]const u8{ "AL", "EQ", "NE", "CS", "CC", "MI", "PL", "VS", "VC", "HI", "LS", "GE", "LT", "GT", "LE" };
pub const Instruction = struct {
    word: u16,
    major: u4,
    sub: u4,
    d: u3,
    s: u3,
    len: u3 = 2,
};
pub fn decode(w: u16) error{InvalidOpcode}!Instruction {
    const major: u4 = @truncate(w >> 12);
    const sub: u4 = @truncate(w >> 8);
    var i: Instruction = .{ .word = w, .major = major, .sub = sub, .d = @truncate(w >> 9), .s = @truncate(w >> 6) };
    switch (major) {
        0 => if (w > 5) return error.InvalidOpcode,
        1, 3...8 => if (w & 63 != 0) return error.InvalidOpcode,
        2 => {
            if (w & 511 != 0) return error.InvalidOpcode;
            i.len = 4;
        },
        9...12 => {},
        13 => if (sub == 15) return error.InvalidOpcode,
        14 => {
            if (sub > 3 or w & 31 != 0) return error.InvalidOpcode;
            i.d = @truncate(w >> 5);
            if (sub < 2) {
                if (w & 255 != 0) return error.InvalidOpcode;
                i.len = 4;
            }
        },
        15 => {
            if (sub > 11 or w & 3 != 0) return error.InvalidOpcode;
            i.d = @truncate(w >> 5);
            i.s = @truncate(w >> 2);
            if ((sub == 3 or sub >= 6) and i.s != 0) return error.InvalidOpcode;
            if (sub == 6 or sub == 7) i.len = 4;
        },
    }
    return i;
}
pub fn executable(a: u16) bool {
    return a & 1 == 0 and (a < ram_end or a >= rom_base);
}
test "decoder exhaustively rejects reserved aliases" {
    for (0..65536) |n| {
        const w: u16 = @intCast(n);
        if (decode(w)) |i| {
            try std.testing.expect(i.len == 2 or i.len == 4);
            if (i.major == 2) try std.testing.expect(w & 511 == 0);
        } else |_| {}
    }
    for ([_]u16{ 6, 0x1001, 0x2040, 0xdf00, 0xe001, 0xe401, 0xf301, 0xf304, 0xfc00 }) |w|
        try std.testing.expectError(error.InvalidOpcode, decode(w));
}

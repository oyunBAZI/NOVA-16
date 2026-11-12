const std = @import("std");
const isa = @import("../arch/isa.zig");
pub const Kind = enum { system, rr, immediate, memory, branch, absolute, reg, extended, unary, ext_imm };
pub const Op = struct { kind: Kind, index: u16, len: u3 = 2 };
pub fn lookup(name: []const u8) !Op {
    return lookupProfile(name, .v1);
}
pub fn lookupProfile(name: []const u8, profile: isa.Profile) !Op {
    if (profile == .v2) for (isa.v2_system_names, 6..) |n, k| {
        if (std.ascii.eqlIgnoreCase(n, name)) return .{ .kind = .system, .index = @intCast(k) };
    };
    for (isa.system_names, 0..) |n, k| if (std.ascii.eqlIgnoreCase(n, name)) return .{ .kind = .system, .index = @intCast(k) };
    for (isa.major_names[1..], 1..) |n, k| if (std.ascii.eqlIgnoreCase(n, name)) return .{ .kind = if (k == 2) .immediate else if (k >= 9) .memory else .rr, .index = @intCast(k), .len = if (k == 2) 4 else 2 };
    for (isa.ext_names, 0..) |n, k| if (std.ascii.eqlIgnoreCase(n, name)) return .{ .kind = if (k == 6 or k == 7) .ext_imm else if (k == 3 or k >= 8) .unary else .extended, .index = @intCast(k), .len = if (k == 6 or k == 7) 4 else 2 };
    for (isa.control_names, 0..) |n, k| if (std.ascii.eqlIgnoreCase(n, name)) return .{ .kind = if (k < 2) .absolute else .reg, .index = @intCast(k), .len = if (k < 2) 4 else 2 };
    if (name.len > 2 and std.ascii.eqlIgnoreCase(name[0..2], "B.")) for (isa.condition_names, 0..) |n, k| {
        if (std.ascii.eqlIgnoreCase(n, name[2..])) return .{ .kind = .branch, .index = @intCast(k) };
    };
    return error.UnknownMnemonic;
}
pub fn reg(s: []const u8) !u16 {
    if (s.len != 2 or std.ascii.toUpper(s[0]) != 'R' or s[1] < '0' or s[1] > '7') return error.ExpectedRegister;
    return s[1] - '0';
}

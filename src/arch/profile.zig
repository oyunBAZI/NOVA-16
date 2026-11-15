//! Explicit ROM-selected hardware contract. Never inferred from guest bytes.
pub const Profile = enum(u16) {
    v1 = 1,
    v2 = 2,
    pub fn parse(name: []const u8) !Profile {
        const std = @import("std");
        if (std.mem.eql(u8, name, "nova16-v1")) return .v1;
        if (std.mem.eql(u8, name, "nova16-v2")) return .v2;
        return error.BadArchitecture;
    }
};

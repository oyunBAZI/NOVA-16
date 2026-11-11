const isa = @import("../arch/isa.zig");
const Fault = @import("traps.zig").Fault;
pub const Bus = struct {
    bytes: [65536]u8 = @splat(0),
    pub fn fetch(self: *Bus, a: u16) Fault!u16 {
        if (a & 1 != 0) return error.Unaligned;
        if (!isa.executable(a)) return error.ExecuteDenied;
        return self.read16(a);
    }
    pub fn read8(self: *Bus, a: u16) Fault!u8 {
        return self.bytes[a];
    }
    pub fn read16(self: *Bus, a: u16) Fault!u16 {
        if (a & 1 != 0) return error.Unaligned;
        return @as(u16, try self.read8(a)) | (@as(u16, try self.read8(a + 1)) << 8);
    }
    pub fn write8(self: *Bus, a: u16, v: u8) Fault!void {
        if (a >= isa.rom_base) return error.WriteDenied;
        self.bytes[a] = v;
    }
    pub fn write16(self: *Bus, a: u16, v: u16) Fault!void {
        if (a & 1 != 0) return error.Unaligned;
        try self.write8(a, @truncate(v));
        try self.write8(a + 1, @truncate(v >> 8));
    }
};

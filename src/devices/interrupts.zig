//! Profile2 IRQ controller and slot timer. No host clock or I/O.
const Fault = @import("../core/traps.zig").Fault;
pub const Frame = struct { top: u16 = 0, vector: u8 = 0 };
pub const Interrupts = struct {
    pending: u8 = 0,
    mask: u8 = 0,
    ie: bool = false,
    depth: u8 = 0,
    frames: [8]Frame = @splat(.{}),
    period: u32 = 0,
    remaining: u32 = 0,
    reload: bool = false,
    pub fn active(self: *const Interrupts) u8 {
        return if (self.depth == 0) 0xff else self.frames[self.depth - 1].vector;
    }
    pub fn selected(self: *const Interrupts) ?u8 {
        if (!self.ie) return null;
        const bits = self.pending & ~self.mask & 3;
        if (bits & 1 != 0) return 0;
        if (bits & 2 != 0) return 1;
        return null;
    }
    pub fn tick(self: *Interrupts) void {
        if (self.remaining == 0) return;
        self.remaining -= 1;
        if (self.remaining == 0) {
            self.pending |= 2;
            if (self.reload) self.remaining = self.period;
        }
    }
    pub fn permitted(a: u16, is_write: bool) bool {
        return switch (a) {
            0xd950...0xd951, 0xd960...0xd963, 0xd968 => true,
            0xd952...0xd953, 0xd964...0xd967 => !is_write,
            else => false,
        };
    }
    pub fn read(self: *const Interrupts, a: u16) u8 {
        return switch (a) {
            0xd950 => self.pending,
            0xd951 => self.mask,
            0xd952 => @intFromBool(self.ie),
            0xd953 => self.active(),
            0xd960...0xd963 => @truncate(self.period >> @as(u5, @intCast((a - 0xd960) * 8))),
            0xd964...0xd967 => @truncate(self.remaining >> @as(u5, @intCast((a - 0xd964) * 8))),
            0xd968 => @intFromBool(self.reload),
            else => unreachable,
        };
    }
    /// Candidate write; period is rearmed once after a complete transaction.
    pub fn write(self: *Interrupts, a: u16, value: u8) Fault!void {
        switch (a) {
            0xd950, 0xd951 => {
                if (value & 0xfc != 0) return error.ReservedBits;
                if (a == 0xd950) self.pending &= ~value else self.mask = value;
            },
            0xd960...0xd963 => {
                const shift: u5 = @intCast((a - 0xd960) * 8);
                self.period = (self.period & ~(@as(u32, 255) << shift)) | (@as(u32, value) << shift);
            },
            0xd968 => {
                if (value & 0xfe != 0) return error.ReservedBits;
                self.reload = value != 0;
            },
            else => unreachable,
        }
    }
};

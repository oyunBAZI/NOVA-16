//! Profile2 integer sound chip. PCM ownership transfers only at frame completion.
const std = @import("std");
const Fault = @import("../core/traps.zig").Fault;
pub const Voice = struct {
    step: u32 = 0,
    phase: u32 = 0,
    noise: u16 = 0xace1,
    volume: u8 = 0,
    wave: u8 = 0,
    enabled: bool = false,
    pub fn sample(self: *Voice) i32 {
        if (!self.enabled) return 0;
        const h: i32 = @intCast(self.phase >> 16);
        const value: i32 = switch (self.wave) {
            0 => if (self.phase < 0x80000000) 32767 else -32767,
            1 => h - 32768,
            2 => if (h < 32768) 2 * h - 32768 else 98303 - 2 * h,
            3 => blk: {
                const bit = (self.noise ^ (self.noise >> 2) ^ (self.noise >> 3) ^ (self.noise >> 5)) & 1;
                self.noise = (self.noise >> 1) | (bit << 15);
                break :blk if (self.noise & 1 != 0) @as(i32, 32767) else -32767;
            },
            else => unreachable,
        };
        self.phase +%= self.step;
        return @divTrunc(value * @as(i32, self.volume), 255);
    }
};
pub const Audio = struct {
    enabled: bool = false,
    gain: u8 = 255,
    generated: u64 = 0,
    voices: [4]Voice = .{ .{}, .{ .noise = 0xace0 }, .{ .noise = 0xace3 }, .{ .noise = 0xace2 } },
    pcm: [800]i16 = @splat(0),
    prefix: u16 = 0,
    pub fn sample(self: *Audio) i16 {
        if (!self.enabled) return 0;
        var total: i32 = 0;
        for (&self.voices) |*v| total += v.sample();
        return @intCast(@divTrunc(@divTrunc(total, 4) * @as(i32, self.gain), 255));
    }
    pub fn permitted(a: u16, is_write: bool) bool {
        if (a < 0xd900 or a > 0xd945) return false;
        if (a < 0xd940) return switch (a & 15) {
            0...6 => true,
            8...13 => !is_write,
            else => false,
        };
        return a <= 0xd941 or !is_write;
    }
    pub fn read(self: *const Audio, a: u16) u8 {
        if (a < 0xd940) {
            const v = &self.voices[(a - 0xd900) / 16];
            const offset = a & 15;
            return switch (offset) {
                0...3 => @truncate(v.step >> @as(u5, @intCast(offset * 8))),
                4 => v.volume,
                5 => v.wave,
                6 => @intFromBool(v.enabled),
                8...11 => @truncate(v.phase >> @as(u5, @intCast((offset - 8) * 8))),
                12...13 => @truncate(v.noise >> @as(u4, @intCast((offset - 12) * 8))),
                else => unreachable,
            };
        }
        return switch (a) {
            0xd940 => @intFromBool(self.enabled),
            0xd941 => self.gain,
            0xd942...0xd945 => @truncate(self.generated >> @as(u6, @intCast((a - 0xd942) * 8))),
            else => unreachable,
        };
    }
    /// Apply to a candidate only. Step range is checked after the whole write.
    pub fn write(self: *Audio, a: u16, value: u8) Fault!void {
        if (a < 0xd940) {
            const index = (a - 0xd900) / 16;
            const v = &self.voices[index];
            const offset = a & 15;
            switch (offset) {
                0...3 => {
                    const shift: u5 = @intCast(offset * 8);
                    v.step = (v.step & ~(@as(u32, 255) << shift)) | (@as(u32, value) << shift);
                },
                4 => v.volume = value,
                5 => {
                    if (value > 3) return error.DeviceValue;
                    v.wave = value;
                },
                6 => {
                    if (value & 0xfc != 0) return error.ReservedBits;
                    v.enabled = value & 1 != 0;
                    if (value & 2 != 0) {
                        v.phase = 0;
                        v.noise = 0xace1 ^ @as(u16, @intCast(index));
                    }
                },
                else => unreachable,
            }
        } else if (a == 0xd940) {
            if (value & 0xfc != 0) return error.ReservedBits;
            self.enabled = value & 1 != 0;
            if (value & 2 != 0) for (&self.voices, 0..) |*v, i| {
                v.phase = 0;
                v.noise = 0xace1 ^ @as(u16, @intCast(i));
            };
        } else self.gain = value;
    }
};
/// Canonical signed16 mono WAV. Caller owns allocation; no guest-clock effects.
pub fn wav(a: std.mem.Allocator, samples: []const i16) ![]u8 {
    if (samples.len > (std.math.maxInt(u32) - 36) / 2) return error.AudioLimit;
    const data = try a.alloc(u8, 44 + samples.len * 2);
    @memcpy(data[0..4], "RIFF");
    std.mem.writeInt(u32, data[4..8], @intCast(data.len - 8), .little);
    @memcpy(data[8..16], "WAVEfmt ");
    std.mem.writeInt(u32, data[16..20], 16, .little);
    std.mem.writeInt(u16, data[20..22], 1, .little);
    std.mem.writeInt(u16, data[22..24], 1, .little);
    std.mem.writeInt(u32, data[24..28], 48000, .little);
    std.mem.writeInt(u32, data[28..32], 96000, .little);
    std.mem.writeInt(u16, data[32..34], 2, .little);
    std.mem.writeInt(u16, data[34..36], 16, .little);
    @memcpy(data[36..40], "data");
    std.mem.writeInt(u32, data[40..44], @intCast(samples.len * 2), .little);
    for (samples, 0..) |sample, i| std.mem.writeInt(i16, data[44 + i * 2 ..][0..2], sample, .little);
    return data;
}

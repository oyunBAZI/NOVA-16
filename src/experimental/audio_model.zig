//! Arithmetic experiment only. Not imported by the emulator or any guest device.
//! No MMIO, interrupts, sound playback or new machine format is implemented here.
const std = @import("std");
pub const Wave = enum { square, saw, triangle, noise };
pub const Voice = struct {
    phase: u32 = 0,
    increment: u32 = 0,
    volume: u8 = 255,
    enabled: bool = false,
    wave: Wave = .square,
    noise: u16 = 1,
    pub fn setFrequency(self: *Voice, hz: u32) !void {
        if (hz > 24000) return error.FrequencyRange;
        self.increment = @intCast((@as(u64, hz) << 32) / 48000);
    }
    pub fn next(self: *Voice) i32 {
        if (!self.enabled) return 0;
        const high: i32 = @intCast(self.phase >> 16);
        const value: i32 = switch (self.wave) {
            .square => if (self.phase < 0x80000000) 32767 else -32767,
            .saw => high - 32768,
            .triangle => if (high < 32768) high * 2 - 32768 else 98303 - high * 2,
            .noise => blk: {
                const bit = (self.noise ^ (self.noise >> 2) ^ (self.noise >> 3) ^ (self.noise >> 5)) & 1;
                self.noise = (self.noise >> 1) | (bit << 15);
                break :blk if (self.noise & 1 != 0) @as(i32, 32767) else -32767;
            },
        };
        self.phase +%= self.increment;
        return @divTrunc(value * @as(i32, self.volume), 255);
    }
};
pub const Mixer = struct {
    voices: [4]Voice = @splat(.{}),
    gain: u8 = 255,
    pub fn next(self: *Mixer) i16 {
        var total: i32 = 0;
        for (&self.voices) |*voice| total += voice.next();
        return @intCast(@divTrunc(@divTrunc(total, 4) * @as(i32, self.gain), 255));
    }
};
pub const SlotClock = struct {
    remainder: u5 = 0,
    pub fn sampleDue(self: *SlotClock) bool {
        self.remainder += 1;
        if (self.remainder == 25) {
            self.remainder = 0;
            return true;
        }
        return false;
    }
};
test "quarter-cycle oscillator vectors and rejected frequency are exact" {
    var voice: Voice = .{ .enabled = true };
    try voice.setFrequency(12000);
    for ([_]i32{ 32767, 32767, -32767, -32767 }) |value| try std.testing.expectEqual(value, voice.next());
    try std.testing.expectEqual(0, voice.phase);
    const previous = voice;
    try std.testing.expectError(error.FrequencyRange, voice.setFrequency(24001));
    try std.testing.expectEqualDeep(previous, voice);
    voice.wave = .saw;
    for ([_]i32{ -32768, -16384, 0, 16384 }) |value| try std.testing.expectEqual(value, voice.next());
    voice.wave = .triangle;
    for ([_]i32{ -32768, 0, 32767, -1 }) |value| try std.testing.expectEqual(value, voice.next());
}
test "fixed slot clock emits 800 samples per frame and resumes by value" {
    var clock: SlotClock = .{};
    var count: usize = 0;
    for (0..20000) |_| if (clock.sampleDue()) {
        count += 1;
    };
    try std.testing.expectEqual(800, count);
    var mixer: Mixer = .{};
    mixer.voices[0] = .{ .enabled = true, .wave = .noise, .noise = 1 };
    for (0..137) |_| _ = mixer.next();
    var copy = mixer;
    for (0..800) |_| try std.testing.expectEqual(mixer.next(), copy.next());
    try std.testing.expectEqualDeep(mixer, copy);
}
test "noise feedback vector, waveform bounds and muted phase behavior" {
    var voice: Voice = .{ .enabled = true, .wave = .noise };
    for ([_]u16{ 0x8000, 0x4000, 0x2000, 0x1000, 0x800, 0x400, 0x200, 0x100 }) |state| {
        _ = voice.next();
        try std.testing.expectEqual(state, voice.noise);
    }
    for ([_]Wave{ .square, .saw, .triangle, .noise }) |wave| {
        voice = .{ .wave = wave, .enabled = true, .increment = 0x7fffffff };
        for (0..65536) |_| {
            const sample = voice.next();
            try std.testing.expect(sample >= -32768 and sample <= 32767);
        }
    }
    var mixer: Mixer = .{};
    mixer.voices[0] = .{ .enabled = true, .increment = 1 };
    mixer.gain = 0;
    try std.testing.expectEqual(0, mixer.next());
    try std.testing.expectEqual(1, mixer.voices[0].phase);
    mixer.voices[0].enabled = false;
    _ = mixer.next();
    try std.testing.expectEqual(1, mixer.voices[0].phase);
}

const std = @import("std");
pub const Input = struct {
    held: u8 = 0,
    pressed: u8 = 0,
    pub fn inject(self: *Input, bits: u8) void {
        self.pressed |= bits & ~self.held;
        self.held = bits;
    }
    pub fn readPressed(self: *Input) u8 {
        const v = self.pressed;
        self.pressed = 0;
        return v;
    }
};
test "edges latch until read and releases do not latch" {
    var i: Input = .{};
    i.inject(1);
    i.inject(1);
    i.inject(0);
    i.inject(2);
    try std.testing.expectEqual(3, i.readPressed());
    try std.testing.expectEqual(0, i.readPressed());
    try std.testing.expectEqual(2, i.held);
}

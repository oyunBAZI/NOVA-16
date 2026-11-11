const std = @import("std");
pub const version = "0.1.0";
test "foundation" {
    try std.testing.expectEqualStrings("0.1.0", version);
}

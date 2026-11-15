const std = @import("std");
const n = @import("nova16");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len > 5) return error.Usage_CASES_SEED_DEPTH_PROFILE;
    const cases = if (args.len > 1) try std.fmt.parseInt(usize, args[1], 0) else 1000;
    const seed = if (args.len > 2) try std.fmt.parseInt(u64, args[2], 0) else 0x4e31364f5054;
    if (cases == 0 or cases > 1000000) return error.CampaignLimit;
    const depth = if (args.len > 3) try std.fmt.parseInt(u8, args[3], 0) else 3;
    const profile = if (args.len > 4) try std.fmt.parseInt(u8, args[4], 0) else 1;
    if (profile != 1 and profile != 2) return error.InvalidProfile;
    const report = try n.compiler_campaign.runWithOptions(std.heap.page_allocator, seed, cases, depth, if (profile == 1) .v1 else .v2);
    var out: std.Io.Writer.Allocating = .init(init.arena.allocator());
    try std.json.Stringify.value(report, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');
    try std.Io.File.stdout().writeStreamingAll(init.io, out.written());
}

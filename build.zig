const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const gui = b.option(bool, "gui", "Enable optional SDL2 frontend") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "gui", gui);
    const core = b.addModule("nova16", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    inline for (.{.{ "nova16", "src/cli/nova16_main.zig" }}) |item| {
        const exe = b.addExecutable(.{ .name = item[0], .root_module = b.createModule(.{ .root_source_file = b.path(item[1]), .target = target, .optimize = optimize }) });
        exe.root_module.addImport("nova16", core);
        exe.root_module.addOptions("options", options);
        b.installArtifact(exe);
    }
    const unit = b.addTest(.{ .root_module = core });
    b.step("test", "Run automated tests").dependOn(&b.addRunArtifact(unit).step);
    const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("src"), b.path("tests") }, .check = true });
    b.step("fmt", "Check formatting").dependOn(&fmt.step);
}

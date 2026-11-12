const std = @import("std");
fn coreModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const core = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    core.addAnonymousImport("examples", .{ .root_source_file = b.path("examples/sources.zig") });
    return core;
}
fn executable(b: *std.Build, name: []const u8, source: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, core: *std.Build.Module, strip: bool) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{ .name = name, .root_module = b.createModule(.{ .root_source_file = b.path(source), .target = target, .optimize = optimize, .strip = strip }) });
    exe.root_module.addImport("nova16", core);
    return exe;
}
fn linkGui(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.root_module.link_libc = true;
    exe.root_module.addCSourceFile(.{ .file = b.path("src/frontend/sdl_adapter.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
    exe.root_module.linkSystemLibrary("SDL2", .{});
}
pub fn build(b: *std.Build) void {
    const v = @import("builtin").zig_version;
    if (v.major != 0 or v.minor != 17 or v.patch != 1) @compileError("NOVA-16 requires Zig 0.17.1");
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Strip debug information from distributable executables") orelse false;
    const gui = b.option(bool, "gui", "Enable optional SDL2 frontend (requires target SDL2 development libraries)") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "gui", gui);
    const core = coreModule(b, target, optimize);
    // Asset generators execute on the build host, never on the selected target.
    const host_core = coreModule(b, b.graph.host, optimize);
    const host_assembler = executable(b, "n16asm-build-host", "src/cli/assembler_main.zig", b.graph.host, optimize, host_core, strip);
    inline for (.{ .{ "nova16", "src/cli/nova16_main.zig" }, .{ "n16asm", "src/cli/assembler_main.zig" }, .{ "n16dbg", "src/cli/debugger_main.zig" } }) |item| {
        const exe = executable(b, item[0], item[1], target, optimize, core, strip);
        exe.root_module.addOptions("options", options);
        if (gui and std.mem.eql(u8, item[0], "nova16")) {
            linkGui(b, exe);
        }
        b.installArtifact(exe);
    }
    const benchmark = executable(b, "n16bench", "src/cli/benchmark_main.zig", b.graph.host, optimize, host_core, strip);
    benchmark.root_module.addImport("examples", host_core.import_table.get("examples").?);
    const run_bench = b.addRunArtifact(benchmark);
    run_bench.addPassthruArgs();
    run_bench.has_side_effects = true;
    b.step("bench", "Measure CPU, frames, initialization, reset, bus, video, loader and assembler").dependOn(&run_bench.step);
    b.step("bench-build", "Install native benchmark executable").dependOn(&b.addInstallArtifact(benchmark, .{}).step);
    if (gui) {
        const test_gui = executable(b, "n16gui-tests", "src/cli/gui_test_main.zig", target, optimize, core, strip);
        linkGui(b, test_gui);
        b.step("gui-test", "Verify SDL events, controls, actual renderer output and integer scaling").dependOn(&b.addRunArtifact(test_gui).step);
    }
    const demos = b.step("demos", "Assemble platform-independent guest ROMs with a native build-host tool");
    inline for (.{ "boot_splash", "bouncing_pixel", "paint", "diagnostics" }) |name| {
        const assemble = b.addRunArtifact(host_assembler);
        assemble.addFileArg(b.path("examples/" ++ name ++ ".asm"));
        assemble.addArg("--out");
        const image = assemble.addOutputFileArg(name ++ ".n16");
        assemble.addArg("--symbols");
        const symbols = assemble.addOutputFileArg(name ++ ".sym");
        const install = b.addInstallFile(image, "demos/" ++ name ++ ".n16");
        const install_symbols = b.addInstallFile(symbols, "demos/" ++ name ++ ".sym");
        demos.dependOn(&install.step);
        demos.dependOn(&install_symbols.step);
        b.getInstallStep().dependOn(&install.step);
        b.getInstallStep().dependOn(&install_symbols.step);
    }
    // `test` always executes native host tests. Native OS CI validates each target.
    const unit = b.addTest(.{ .root_module = host_core });
    b.step("test", "Run native build-host automated tests").dependOn(&b.addRunArtifact(unit).step);
    const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("src"), b.path("examples/sources.zig") }, .check = true });
    b.step("fmt", "Check formatting").dependOn(&fmt.step);
}

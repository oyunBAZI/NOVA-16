//! Reproducible grammar-based compiler differential campaign. It runs generated
//! ROMs on the real CPU and compares to the separate wide-integer AST oracle.
//! Linked only by the opt-in maintainer executable, never a guest runtime.
const std = @import("std");
const compiler = @import("compiler.zig");
const Reference = @import("reference.zig").Interpreter;
const Machine = @import("../core/machine.zig").Machine;
pub const Report = struct { schema_version: u16 = 1, seed: u64, cases: usize, rom_executions: usize = 0, retired: u64 = 0, optimized_bytes: u64 = 0, baseline_bytes: u64 = 0, optimized_instructions: u64 = 0, baseline_instructions: u64 = 0, maximum_source_bytes: usize = 0, expression_depth: u8 = 3, architecture: []const u8 = "nova16-v1" };
const Generator = struct {
    random: std.Random,
    writer: *std.Io.Writer,
    fn integer(self: *Generator, depth: u8) anyerror!void {
        const w = self.writer;
        if (depth == 0) {
            switch (self.random.uintLessThan(u8, 5)) {
                0 => try w.writeAll("a"),
                1 => try w.writeAll("b"),
                2 => try w.writeAll("tap(a)"),
                else => try w.print("{d}", .{self.random.int(u16)}),
            }
            return;
        }
        switch (self.random.uintLessThan(u8, 15)) {
            0...7 => |kind| {
                try w.writeByte('(');
                try self.integer(depth - 1);
                const operators = [_][]const u8{ "+", "-", "*", "&", "|", "^", "<<", ">>" };
                try w.print("{s}", .{operators[kind]});
                try self.integer(depth - 1);
                try w.writeByte(')');
            },
            8, 9 => |kind| {
                try w.writeAll("(");
                try self.integer(depth - 1);
                try w.writeAll(if (kind == 8) "/(" else "%(");
                try self.integer(depth - 1);
                try w.writeAll("|1))");
            },
            10, 11 => |kind| {
                try w.writeAll("u16(i16(");
                try self.integer(depth - 1);
                try w.writeAll(if (kind == 10) ")/i16((" else ")%i16((");
                try self.integer(depth - 1);
                try w.writeAll("|1)))");
            },
            12 => {
                try w.writeAll("(");
                try self.boolean(depth - 1);
                try w.writeByte('?');
                try self.integer(depth - 1);
                try w.writeByte(':');
                try self.integer(depth - 1);
                try w.writeByte(')');
            },
            13 => {
                try w.writeAll("u16(i16(");
                try self.integer(depth - 1);
                try w.writeAll(")>>");
                try self.integer(depth - 1);
                try w.writeByte(')');
            },
            else => {
                try w.writeAll("(~");
                try self.integer(depth - 1);
                try w.writeByte(')');
            },
        }
    }
    fn boolean(self: *Generator, depth: u8) anyerror!void {
        if (depth > 0 and self.random.boolean()) {
            try self.writer.writeByte('(');
            try self.boolean(depth - 1);
            try self.writer.writeAll(if (self.random.boolean()) "&&" else "||");
            try self.boolean(depth - 1);
            try self.writer.writeByte(')');
        } else {
            try self.writer.writeByte('(');
            try self.integer(0);
            const ops = [_][]const u8{ "<", ">", "<=", ">=", "==", "!=" };
            try self.writer.writeAll(ops[self.random.uintLessThan(u8, ops.len)]);
            try self.integer(0);
            try self.writer.writeByte(')');
        }
    }
};
fn verify(a: std.mem.Allocator, result: compiler.Result, expected: u16, reference: *const Reference) !u64 {
    const m = try a.create(Machine);
    defer a.destroy(m);
    m.* = .{};
    try m.load(result.program.image);
    for (0..1000000) |_| {
        m.step();
        if (m.cpu.halted or m.cpu.paused or m.cpu.trap != null) break;
    }
    if (!m.cpu.halted or m.cpu.paused or m.cpu.trap != null or m.cpu.r[0] != expected or m.cpu.sp != 0xbffe or m.cpu.r[7] != 0x8000) return error.CompilerOracleMismatch;
    for (result.context.variables.items, 0..) |variable, index| {
        if (variable.function != compiler.syntax.none or variable.constant) continue;
        for (0..result.context.tree.types[variable.ty].words) |word| {
            const value = try m.bus.read16(variable.address + @as(u16, @intCast(word * 2)));
            if (value != reference.globals[reference.slots[index] + word]) return error.CompilerSideEffectMismatch;
        }
    }
    try m.validateState();
    return m.cpu.retired;
}
pub fn run(a: std.mem.Allocator, seed: u64, cases: usize) !Report {
    return runWithOptions(a, seed, cases, 3, .v1);
}
pub fn runWithOptions(a: std.mem.Allocator, seed: u64, cases: usize, depth: u8, profile: @import("../arch/profile.zig").Profile) !Report {
    if (depth < 2 or depth > 4) return error.CampaignDepth;
    var prng = std.Random.DefaultPrng.init(seed);
    var report: Report = .{ .seed = seed, .cases = cases, .expression_depth = depth, .architecture = if (profile == .v1) "nova16-v1" else "nova16-v2" };
    for (0..cases) |index| {
        var source: std.Io.Writer.Allocating = .init(a);
        defer source.deinit();
        try source.writer.print("var events:u16=0; var g:u16={d}; var cells:[8]u16; fn tap(x:u16)->u16{{events=events*17+x;return x;}} fn mix(a:u16,b:u16)->u16{{return ", .{prng.random().int(u16)});
        var generator: Generator = .{ .random = prng.random(), .writer = &source.writer };
        try generator.integer(depth - 1 + @as(u8, @intCast(index % 2)));
        try source.writer.print(";}} fn main()->u16{{var i:u16=0;while(i<4){{cells[i]=mix(tap(g+i),tap({d}^i));i=i+1;}}return cells[0]+cells[3]+events;}}", .{prng.random().int(u16)});
        report.maximum_source_bytes = @max(report.maximum_source_bytes, source.written().len);
        var diagnostic: compiler.Diagnostic = .{};
        const baseline = compiler.compileWithOptions(a, source.written(), &diagnostic, .{ .optimization = .none, .profile = profile }) catch |err| {
            std.debug.print("seed={d} case={d} baseline {s} {d}:{d}\n{s}\n", .{ seed, index, @errorName(err), diagnostic.line, diagnostic.column, source.written() });
            return err;
        };
        defer baseline.deinit();
        const optimized = try compiler.compileWithOptions(a, source.written(), &diagnostic, .{ .profile = profile });
        defer optimized.deinit();
        var reference: Reference = .{ .context = baseline.context };
        const expected = try reference.run();
        const slow = verify(a, baseline, expected, &reference) catch |err| {
            std.debug.print("seed={d} case={d} baseline {s}\n{s}\n", .{ seed, index, @errorName(err), source.written() });
            return err;
        };
        const fast = verify(a, optimized, expected, &reference) catch |err| {
            std.debug.print("seed={d} case={d} optimized {s}\n{s}\n", .{ seed, index, @errorName(err), source.written() });
            return err;
        };
        if (optimized.program.image.len > baseline.program.image.len) return error.CompilerSizeRegression;
        report.rom_executions += 2;
        report.retired += slow + fast;
        report.baseline_instructions += slow;
        report.optimized_instructions += fast;
        report.baseline_bytes += baseline.program.image.len - 32;
        report.optimized_bytes += optimized.program.image.len - 32;
        if (index > 0 and index % 1000 == 0) std.debug.print("compiler campaign seed={d}: {d}/{d} cases passed\n", .{ seed, index, cases });
    }
    return report;
}

const std = @import("std");
const compiler = @import("compiler/compiler.zig");
const Machine = @import("core/machine.zig").Machine;
test "typed compiler emits ordinary guest instructions and real nested calls" {
    const source = "struct Point { x:u16; y:i16; } var total:u16=2; fn add(a:u16,b:u16)->u16 { return a+b; } fn main()->u16 { var p:Point; p.x=19; p.y=-3; var a:[4]u16; a[2]=23; var i:u16=0; while(i<3){ total=total+1; i=i+1; } if(p.y<0){total=add(p.x,a[2]);}else{total=0;} return total; }";
    var d: compiler.Diagnostic = .{};
    const result = compiler.compile(std.testing.allocator, source, &d) catch |err| {
        std.debug.print("compiler {s} {d}:{d} {s}\n", .{ @errorName(err), d.line, d.column, d.token });
        return err;
    };
    defer result.deinit();
    var m: Machine = .{};
    try m.load(result.program.image);
    for (0..100000) |_| {
        m.step();
        if (m.cpu.halted or m.cpu.paused or m.cpu.trap != null) break;
    }
    try std.testing.expect(m.cpu.halted and m.cpu.trap == null);
    try std.testing.expectEqual(42, m.cpu.r[0]);
    try std.testing.expectEqual(0x8000, m.cpu.r[7]);
    try std.testing.expectEqual(0xbffe, m.cpu.sp);
}

fn execute(source: []const u8, expected: u16) !void {
    var d: compiler.Diagnostic = .{};
    const r = compiler.compile(std.testing.allocator, source, &d) catch |err| {
        std.debug.print("compile case {s} at {d}:{d} {s}\n{s}\n", .{ @errorName(err), d.line, d.column, d.token, source });
        return err;
    };
    defer r.deinit();
    var m: Machine = .{};
    try m.load(r.program.image);
    for (0..1000000) |_| {
        m.step();
        if (m.cpu.halted or m.cpu.paused or m.cpu.trap != null) break;
    }
    try std.testing.expect(m.cpu.halted and !m.cpu.paused and m.cpu.trap == null);
    try std.testing.expectEqual(expected, m.cpu.r[0]);
    try std.testing.expectEqual(0xbffe, m.cpu.sp);
    const again = try compiler.compile(std.testing.allocator, source, &d);
    defer again.deinit();
    try std.testing.expectEqualSlices(u8, r.program.image, again.program.image);
}
test "at least 25 positive typed integration cases execute deterministic real ROMs" {
    const Case = struct { expr: []const u8, value: u16 };
    const cases = [_]Case{
        .{ .expr = "42", .value = 42 },                          .{ .expr = "65535+1", .value = 0 },                  .{ .expr = "0-1", .value = 65535 },                 .{ .expr = "65535*2", .value = 65534 },
        .{ .expr = "65535/255", .value = 257 },                  .{ .expr = "65535%255", .value = 0 },                .{ .expr = "15&10", .value = 10 },                  .{ .expr = "8|3", .value = 11 },
        .{ .expr = "15^10", .value = 5 },                        .{ .expr = "~0", .value = 65535 },                   .{ .expr = "1<<15", .value = 32768 },               .{ .expr = "1<<16", .value = 1 },
        .{ .expr = "32768>>15", .value = 1 },                    .{ .expr = "u16(i16(-32768)>>15)", .value = 65535 }, .{ .expr = "u16(i16(-7)/i16(3))", .value = 65534 }, .{ .expr = "u16(i16(-7)%i16(3))", .value = 65535 },
        .{ .expr = "u16(i16(-32768)/i16(-1))", .value = 32768 }, .{ .expr = "u16(65535>0)", .value = 1 },             .{ .expr = "u16(i16(-1)<i16(0))", .value = 1 },     .{ .expr = "u16(true&&false)", .value = 0 },
        .{ .expr = "u16(false||true)", .value = 1 },             .{ .expr = "u16(!false)", .value = 1 },              .{ .expr = "true?7:9", .value = 7 },                .{ .expr = "false?7:9", .value = 9 },
        .{ .expr = "u16(bool(12))", .value = 1 },                .{ .expr = "u16(4==4)", .value = 1 },                .{ .expr = "u16(4!=4)", .value = 0 },               .{ .expr = "u16(4<=4)", .value = 1 },
        .{ .expr = "u16(4>=5)", .value = 0 },
    };
    for (cases) |case| {
        const source = try std.fmt.allocPrint(std.testing.allocator, "fn main()->u16 {{ return {s}; }}", .{case.expr});
        defer std.testing.allocator.free(source);
        try execute(source, case.value);
    }
    try execute("fn f(n:u16)->u16 { if(n==0){return 1;}else{return n*f(n-1);} } fn main()->u16{return f(5);}", 120);
    try execute("fn main()->u16 {var a:[4]u16;var i:u16=0;while(i<4){a[i]=i*3;i=i+1;}return a[3];}", 9);
    try execute("const C:u16=6*7; fn main()->u16 {const x:u16=C;return x;}", 42);
    try execute("fn sum(a:u16,b:u16,c:u16,d:u16)->u16{return a+b+c+d;} fn main()->u16{return sum(1,2,3,4);}", 10);
    try execute("struct S{flag:bool;value:i16;} fn main()->u16 {var s:S;s.flag=true;s.value=-2;return s.flag?u16(s.value):0;}", 65534);
}
test "at least 25 negative typed compiler cases fail without partial successful output" {
    const cases = [_][]const u8{
        "",                                                                "fn x()->u16{return 1;}",                                                "fn main(x:u16)->u16{return x;}",                       "fn main()->u16{}",                                  "fn main()->u16{return true;}",
        "fn main()->u16{return unknown;}",                                 "fn main()->u16{return f();}",                                           "fn main()->u16{return i16(1)+u16(2);}",                "fn main()->u16{var x:u16=1;var x:u16=2;return x;}", "fn main()->u16{const x:u16=1;x=2;return x;}",
        "fn main()->u16{var a:[2]u16;return a[2];}",                       "fn main()->u16{var a:[0]u16;return 0;}",                                "fn main()->u16{var a:[8193]u16;return 0;}",            "fn main()->u16{var a:[129]u16;return 0;}",          "fn main()->u16{var x:u16=true;return x;}",
        "fn main()->u16{if(1){return 1;}else{return 0;}}",                 "fn main()->u16{while(1){}return 0;}",                                   "fn main()->u16{return 1/0;}",                          "fn main()->u16{return 65536;}",                     "fn main()->u16{return u16(-32769);}",
        "fn main()->u16{var x:thing;return 0;}",                           "fn main()->u16{var x:u16=1;return x.nope;}",                            "struct S{x:u16;} fn main()->u16{var s:S;return s.y;}", "struct S{x:u16;x:u16;} fn main()->u16{return 0;}",  "struct S{} fn main()->u16{return 0;}",
        "fn f(a:u16,a:u16)->u16{return a;}fn main()->u16{return f(1,2);}", "fn f()->u16{return 0;}fn f()->u16{return 1;}fn main()->u16{return 0;}", "fn main()->u16{return pixel(1,2);}",                   "fn main()->u16{return u16(1,2);}",                  "fn main()->u16{return 1++2;}",
        "fn main()->u16{return 0;",                                        "/* unterminated",                                                       "\xff",                                                 "fn main()->u16{var if:u16=1;return 0;}",            "fn u16()->u16{return 0;}fn main()->u16{return 0;}",
    };
    for (cases) |source| {
        var d: compiler.Diagnostic = .{};
        if (compiler.compile(std.testing.allocator, source, &d)) |r| {
            r.deinit();
            std.debug.print("unexpected compiler success {s}\n", .{source});
            return error.ExpectedCompileFailure;
        } else |err| {
            try std.testing.expect(err != error.WriteFailed);
            try std.testing.expect(d.code.len > 0);
        }
    }
}
test "dynamic bounds and recursive frame limits fail in guest instructions" {
    for ([_]struct { source: []const u8, code: u16 }{
        .{ .source = "var i:u16=3;fn main()->u16{var a:[2]u16;return a[i];}", .code = 1 },
        .{ .source = "fn f(x:u16)->u16{return 5/x;}fn main()->u16{return f(0);}", .code = 2 },
        .{ .source = "fn f()->u16{return f();}fn main()->u16{return f();}", .code = 3 },
    }) |case| {
        var d: compiler.Diagnostic = .{};
        const r = try compiler.compile(std.testing.allocator, case.source, &d);
        defer r.deinit();
        var m: Machine = .{};
        try m.load(r.program.image);
        for (0..100000) |_| {
            m.step();
            if (m.cpu.paused or m.cpu.halted or m.cpu.trap != null) break;
        }
        try std.testing.expect(m.cpu.paused and m.cpu.trap == null);
        try std.testing.expectEqual(case.code, try m.bus.read16(0xf0));
    }
}

test "compiler resource caps allocation failure and emitted source origins" {
    const a = std.testing.allocator;
    var d: compiler.Diagnostic = .{};
    const large = try a.alloc(u8, 1024 * 1024 + 1);
    defer a.free(large);
    @memset(large, ' ');
    try std.testing.expectError(error.SourceTooLarge, compiler.compile(a, large, &d));
    var deep: std.Io.Writer.Allocating = .init(a);
    defer deep.deinit();
    try deep.writer.writeAll("fn main()->u16{return ");
    for (0..80) |_| try deep.writer.writeByte('(');
    try deep.writer.writeAll("1");
    for (0..80) |_| try deep.writer.writeByte(')');
    try deep.writer.writeAll(";}");
    try std.testing.expectError(error.NestingLimit, compiler.compile(a, deep.written(), &d));
    const source = "var total:u16=1;\nfn main()->u16 {\n  total=42;\n  return total;\n}\n";
    const r = try compiler.compile(a, source, &d);
    defer r.deinit();
    var found = false;
    for (r.program.locations) |loc| if (loc.line == 3 and loc.column >= 3) {
        found = true;
    };
    try std.testing.expect(found);
    const Check = struct {
        fn run(alloc: std.mem.Allocator) !void {
            var diagnostic: compiler.Diagnostic = .{};
            const result = try compiler.compile(alloc, "fn main()->u16{return 42;}", &diagnostic);
            defer result.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(a, Check.run, .{});
}

test "independent bounded AST interpreter agrees with compiled V1 across seeded programs" {
    const Reference = @import("compiler/reference.zig").Interpreter;
    var random = std.Random.DefaultPrng.init(0x4e16c004);
    for (0..192) |case| {
        const x = random.random().int(u16);
        const y = random.random().intRangeAtMost(u16, 1, 65535);
        const shift = random.random().intRangeAtMost(u16, 0, 31);
        const source = try std.fmt.allocPrint(std.testing.allocator, "struct P{{x:u16;y:i16;}} var g:u16={d}; fn mix(a:u16,b:u16)->u16{{var p:P;p.x=a;p.y=i16(b);return (p.x^u16(p.y))+(a>>{d});}} fn main()->u16{{var data:[4]u16;var i:u16=0;while(i<4){{data[i]=mix(g+i,{d});i=i+1;}} var s:i16=i16({d});if(s<i16(0)){{g=u16(s/i16({d}));}}else{{g=data[2]/{d};}} return (data[0]+data[3])^(g+u16(s>>{d}));}}", .{ x, shift, y, x, y, y, shift });
        defer std.testing.allocator.free(source);
        var d: compiler.Diagnostic = .{};
        const r = try compiler.compile(std.testing.allocator, source, &d);
        defer r.deinit();
        var reference: Reference = .{ .context = r.context };
        const expected = try reference.run();
        var m: Machine = .{};
        try m.load(r.program.image);
        for (0..500000) |_| {
            m.step();
            if (m.cpu.halted or m.cpu.paused or m.cpu.trap != null) break;
        }
        if (!m.cpu.halted or m.cpu.trap != null or m.cpu.r[0] != expected) {
            std.debug.print("differential seed4e16c004 case{d} expected{d} actual{d}\n{s}\n", .{ case, expected, m.cpu.r[0], source });
            return error.CompilerDifferentialMismatch;
        }
    }
    var d: compiler.Diagnostic = .{};
    const infinite = try compiler.compile(std.testing.allocator, "fn main()->u16{while(true){}return 0;}", &d);
    defer infinite.deinit();
    var bounded: Reference = .{ .context = infinite.context, .remaining = 100 };
    try std.testing.expectError(error.ReferenceWorkLimit, bounded.run());
}

test "guest linker exact references shared tails recursion data and unsupported layouts" {
    const linker = @import("compiler/guest_linker.zig");
    const library = "unused: RET\nentry: CALL helper\nB.EQ tail\nfall: LDI R0, table+1\nRET\nhelper: CALL helper\nJMP tail\ntail: RET\ntable: .byte 1,2\n.align 2\n";
    const plan = try linker.plan(std.testing.allocator, "CALL entry ; unused\n", library);
    defer plan.deinit();
    for (plan.blocks, 0..) |block, index| try std.testing.expectEqual(index != 0, block.retained);
    const empty = try linker.plan(std.testing.allocator, "LDI R0, 1 ; entry\n", library);
    defer empty.deinit();
    for (empty.blocks) |block| try std.testing.expect(!block.retained);
    try std.testing.expectError(error.UnsupportedLibraryControlFlow, linker.plan(std.testing.allocator, "CALL x", "x: JMP 57344\n"));
    try std.testing.expectError(error.UnsupportedLibraryControlFlow, linker.plan(std.testing.allocator, "CALL x", "x: CALLR R0\n"));
    try std.testing.expectError(error.UnsupportedLibraryDirective, linker.plan(std.testing.allocator, "CALL x", "x: .org 60000\n"));
    try std.testing.expectError(error.DuplicateLibrarySymbol, linker.plan(std.testing.allocator, "CALL x", "x: RET\nx: RET\n"));
}

test "minimal typed program omits guest library and size report accounts for payload" {
    var diagnostic: compiler.Diagnostic = .{};
    const result = try compiler.compile(std.testing.allocator, "fn main()->u16{return 42;}", &diagnostic);
    defer result.deinit();
    try std.testing.expect(result.program.image.len < 256);
    try std.testing.expect(std.mem.indexOf(u8, result.assembly, "n16_font_data:") == null);
    var report: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer report.deinit();
    try compiler.writeSizeReport(&report.writer, std.testing.allocator, result);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, report.written(), .{});
    defer parsed.deinit();
    const object = parsed.value.object;
    try std.testing.expectEqual(@as(i64, @intCast(result.program.image.len - 32)), object.get("rom_payload_bytes").?.integer);
    try std.testing.expectEqual(0, object.get("library_blocks").?.array.items.len);
    try std.testing.expect(object.get("removed_library_blocks").?.integer > 0);
}

test "unreachable typed cycles and their library dependencies are removed with valid maps" {
    const source = "fn dead(n:u16)->u16{var hidden:u16=n;glyph(1,2,65);return other(hidden);} fn other(n:u16)->u16{return dead(n);} fn main()->u16{var live:u16=42;return live;}";
    var diagnostic: compiler.Diagnostic = .{};
    const result = try compiler.compile(std.testing.allocator, source, &diagnostic);
    defer result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, result.assembly, "_c_f_dead:") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.assembly, "n16_glyph:") == null);
    var map: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer map.deinit();
    try compiler.writeDebugMap(&map.writer, std.testing.allocator, result, "main.n16c");
    try std.testing.expect(std.mem.indexOf(u8, map.written(), "hidden") == null);
    try std.testing.expect(std.mem.indexOf(u8, map.written(), "live") != null);
    try execute(source, 42);
    try std.testing.expectError(error.TypeMismatch, compiler.compile(std.testing.allocator, "fn dead()->u16{return true;}fn main()->u16{return 42;}", &diagnostic));
    try execute("fn a(n:u16)->u16{if(n==0){return 42;}else{return b(n-1);}}fn b(n:u16)->u16{return a(n);}fn main()->u16{return a(4);}", 42);
}

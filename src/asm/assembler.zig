const std = @import("std");
const lex = @import("lexer.zig");
const parser = @import("parser.zig");
const enc = @import("encoder.zig");
const isa = @import("../arch/isa.zig");
const rom = @import("../rom/format.zig");
pub const Diagnostic = @import("diagnostic.zig").Diagnostic;
pub const Location = struct { address: u32, length: usize, line: usize, column: usize, source: []const u8 };
pub const Symbol = struct { name: []const u8, value: i64 };
pub const Result = struct {
    image: []u8,
    symbols: []Symbol,
    locations: []Location,
    allocator: std.mem.Allocator,
    pub fn deinit(self: Result) void {
        self.allocator.free(self.image);
        self.allocator.free(self.symbols);
        self.allocator.free(self.locations);
    }
};
const Assembly = struct {
    a: std.mem.Allocator,
    source: []const u8,
    diag: *Diagnostic,
    locations: std.ArrayList(Location) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    pending: std.ArrayList(struct { name: []const u8, expression: []const u8, line: usize }) = .empty,
    line_number: usize = 1,
    bytes: [8192]u8 = @splat(0),
    pc: usize = 0xe000,
    length: usize = 0,
    first: ?usize = null,
    entry: ?[]const u8 = null,
    pass: u1 = 0,
    fn value(self: *Assembly, text: []const u8) !i64 {
        const s = lex.trim(text);
        self.diag.focus(self.source, s);
        if (s.len == 0) return error.ExpectedExpression;
        // Only one +/- numeric suffix is permitted, never arbitrary code.
        for (s[1..], 1..) |c, k| {
            if (c == '+' or c == '-') {
                const base = try self.atom(lex.trim(s[0..k]));
                self.diag.focus(self.source, s);
                const delta = try number(lex.trim(s[k + 1 ..]));
                if (delta < 0) return error.ExpectedExpression;
                return if (c == '+') std.math.add(i64, base, delta) catch return error.Width else std.math.sub(i64, base, delta) catch return error.Width;
            }
        }
        return self.atom(s);
    }
    fn atom(self: *Assembly, s: []const u8) !i64 {
        self.diag.focus(self.source, s);
        if (s.len == 0) return error.ExpectedExpression;
        if (std.ascii.isDigit(s[0]) or s[0] == '-' or s[0] == '+') return number(s);
        for (self.symbols.items) |sym| if (std.mem.eql(u8, s, sym.name)) return sym.value;
        return error.UndefinedSymbol;
    }
    fn symbol(self: *Assembly, name: []const u8, v: i64) !void {
        self.diag.focus(self.source, name);
        if (!lex.identifier(name)) return error.InvalidSymbol;
        for (self.symbols.items) |sym| if (std.mem.eql(u8, name, sym.name)) return error.DuplicateSymbol;
        for (self.pending.items) |sym| if (std.mem.eql(u8, name, sym.name)) return error.DuplicateSymbol;
        try self.symbols.append(self.a, .{ .name = name, .value = v });
    }
    fn unresolved(self: *Assembly) anyerror {
        var expression = self.pending.items[0].expression;
        for (0..self.pending.items.len + 1) |_| {
            self.diag.focus(self.source, expression);
            var end = expression.len;
            for (expression[1..], 1..) |c, k| if (c == '+' or c == '-') {
                end = k;
                break;
            };
            const name = lex.trim(expression[0..end]);
            var next: ?[]const u8 = null;
            for (self.pending.items) |p| if (std.mem.eql(u8, p.name, name)) {
                next = p.expression;
                break;
            };
            expression = next orelse return error.UndefinedSymbol;
        }
        self.diag.focus(self.source, self.pending.items[0].expression);
        return error.CyclicConstant;
    }
    fn emit(self: *Assembly, b: u8) !void {
        if (self.pc >= 65536) return error.RomOverflow;
        if (self.pass == 1) self.bytes[self.pc - 0xe000] = b;
        self.pc += 1;
        self.length = @max(self.length, self.pc - 0xe000);
    }
    fn word(self: *Assembly, w: u16) !void {
        try self.emit(@truncate(w));
        try self.emit(@truncate(w >> 8));
    }
    fn count(p: lex.Parts, n: usize) !void {
        if (p.len != n) return error.OperandCount;
    }
    fn bounded(self: *Assembly, s: []const u8, min: i64, max: i64) !i64 {
        const v = try self.value(s);
        if (v < min or v > max) return error.Width;
        return v;
    }
    fn immediate(self: *Assembly, s: []const u8) !u16 {
        const v = try self.bounded(s, -32768, 65535);
        return @truncate(@as(u64, @bitCast(v)));
    }
    fn string(self: *Assembly, s: []const u8) !void {
        if (s.len < 2 or s[0] != '"' or s[s.len - 1] != '"') return error.ExpectedString;
        var k: usize = 1;
        while (k < s.len - 1) : (k += 1) {
            var c = s[k];
            if (c == '"') return error.ExpectedString;
            if (c == '\\') {
                k += 1;
                if (k >= s.len - 1) return error.ExpectedString;
                c = switch (s[k]) {
                    'n' => 10,
                    'r' => 13,
                    't' => 9,
                    '0' => 0,
                    '\\' => 92,
                    '"' => 34,
                    else => return error.BadEscape,
                };
            }
            try self.emit(c);
        }
    }
    fn register(self: *Assembly, s: []const u8) !u16 {
        self.diag.focus(self.source, s);
        return enc.reg(s);
    }
    fn line(self: *Assembly, l: parser.Line) !void {
        if (l.label) |label| if (self.pass == 0) {
            try self.symbol(label, @intCast(self.pc));
        };
        if (l.name.len == 0) return;
        self.diag.focus(self.source, l.args);
        const p = try lex.operands(l.args);
        const n = l.name;
        if (n[0] == '.') {
            if (std.ascii.eqlIgnoreCase(n, ".org")) {
                try count(p, 1);
                const v: usize = @intCast(try self.bounded(p.items[0], 0xe000, 65535));
                if (v < self.pc) return error.BackwardOrg;
                while (self.pc < v) try self.emit(0);
            } else if (std.ascii.eqlIgnoreCase(n, ".entry")) {
                try count(p, 1);
                if (self.pass == 0) {
                    if (self.entry != null) return error.DuplicateEntry;
                    self.entry = p.items[0];
                }
            } else if (std.ascii.eqlIgnoreCase(n, ".equ")) {
                try count(p, 2);
                if (self.pass == 0) {
                    const resolved = self.value(p.items[1]) catch |err| switch (err) {
                        error.UndefinedSymbol => {
                            try self.symbol(p.items[0], 0);
                            _ = self.symbols.pop();
                            try self.pending.append(self.a, .{ .name = p.items[0], .expression = p.items[1], .line = self.line_number });
                            return;
                        },
                        else => return err,
                    };
                    try self.symbol(p.items[0], resolved);
                }
            } else if (std.ascii.eqlIgnoreCase(n, ".byte") or std.ascii.eqlIgnoreCase(n, ".word")) {
                if (p.len == 0) return error.OperandCount;
                for (p.items[0..p.len]) |v| {
                    if (std.ascii.eqlIgnoreCase(n, ".word")) try self.word(if (self.pass == 0) 0 else try self.immediate(v)) else try self.emit(if (self.pass == 0) 0 else @intCast(try self.bounded(v, 0, 255)));
                }
            } else if (std.ascii.eqlIgnoreCase(n, ".ascii")) {
                try count(p, 1);
                try self.string(p.items[0]);
            } else if (std.ascii.eqlIgnoreCase(n, ".fill")) {
                if (p.len < 1 or p.len > 2) return error.OperandCount;
                const size: usize = @intCast(try self.bounded(p.items[0], 0, 8192));
                const v: u8 = if (p.len == 2) @intCast(try self.bounded(p.items[1], 0, 255)) else 0;
                for (0..size) |_| try self.emit(v);
            } else if (std.ascii.eqlIgnoreCase(n, ".align")) {
                try count(p, 1);
                const v: usize = @intCast(try self.bounded(p.items[0], 1, 8192));
                if (!std.math.isPowerOfTwo(v)) return error.BadAlignment;
                while (self.pc % v != 0) try self.emit(0);
            } else return error.UnknownDirective;
            return;
        }
        if (self.pc & 1 != 0) return error.UnalignedInstruction;
        if (self.first == null) self.first = self.pc;
        self.diag.focus(self.source, n);
        const op = try enc.lookup(n);
        const inst_pc = self.pc;
        if (self.pass == 0) {
            for (0..op.len) |_| try self.emit(0);
            return;
        }
        var w: u16 = 0;
        var imm: u16 = 0;
        switch (op.kind) {
            .system => {
                try count(p, 0);
                w = op.index;
            },
            .rr => {
                try count(p, 2);
                w = (op.index << 12) | (try self.register(p.items[0]) << 9) | (try self.register(p.items[1]) << 6);
            },
            .immediate => {
                try count(p, 2);
                w = 0x2000 | (try self.register(p.items[0]) << 9);
                imm = try self.immediate(p.items[1]);
            },
            .extended => {
                try count(p, 2);
                w = 0xf000 | (op.index << 8) | (try self.register(p.items[0]) << 5) | (try self.register(p.items[1]) << 2);
            },
            .unary => {
                try count(p, 1);
                w = 0xf000 | (op.index << 8) | (try self.register(p.items[0]) << 5);
            },
            .ext_imm => {
                try count(p, 2);
                w = 0xf000 | (op.index << 8) | (try self.register(p.items[0]) << 5);
                imm = try self.immediate(p.items[1]);
            },
            .absolute => {
                try count(p, 1);
                imm = @intCast(try self.bounded(p.items[0], 0, 65535));
                if (!isa.executable(imm)) return error.InvalidTarget;
                w = 0xe000 | (op.index << 8);
            },
            .reg => {
                try count(p, 1);
                w = 0xe000 | (op.index << 8) | (try self.register(p.items[0]) << 5);
            },
            .branch => {
                try count(p, 1);
                const dest = try self.bounded(p.items[0], 0, 65535);
                if (!isa.executable(@intCast(dest))) return error.InvalidTarget;
                const delta = dest - @as(i64, @intCast(inst_pc)) - 2;
                if (@mod(delta, 2) != 0 or delta < -256 or delta > 254) return error.BranchRange;
                const disp: i8 = @intCast(@divExact(delta, 2));
                w = 0xd000 | (op.index << 8) | @as(u8, @bitCast(disp));
            },
            .memory => {
                try count(p, 2);
                const mem = lex.trim(p.items[1]);
                if (mem.len < 4 or mem[0] != '[' or mem[mem.len - 1] != ']') return error.ExpectedMemory;
                const inner = lex.trim(mem[1 .. mem.len - 1]);
                if (inner.len < 2) return error.ExpectedMemory;
                const base = try self.register(inner[0..2]);
                const suffix = lex.trim(inner[2..]);
                var off: i64 = 0;
                if (suffix.len != 0) {
                    if (suffix[0] != '+' and suffix[0] != '-') return error.ExpectedMemory;
                    off = try self.value(lex.trim(suffix[1..]));
                    if (suffix[0] == '-') off = std.math.negate(off) catch return error.Width;
                }
                if (off < -32 or off > 31) return error.DisplacementRange;
                const disp: i6 = @intCast(off);
                w = (op.index << 12) | (try self.register(p.items[0]) << 9) | (base << 6) | @as(u6, @bitCast(disp));
            },
        }
        _ = try isa.decode(w);
        try self.word(w);
        if (op.len == 4) try self.word(imm);
    }
};
fn number(s: []const u8) !i64 {
    return std.fmt.parseInt(i64, s, 0) catch return error.InvalidNumber;
}
pub fn assemble(a: std.mem.Allocator, source: []const u8, diag: *Diagnostic) !Result {
    return assembleInner(a, source, diag) catch |err| {
        diag.explain(err);
        return err;
    };
}
fn assembleInner(a: std.mem.Allocator, source: []const u8, diag: *Diagnostic) !Result {
    diag.* = .{};
    if (source.len > 1024 * 1024) return error.SourceTooLarge;
    var state: Assembly = .{ .a = a, .source = source, .diag = diag };
    defer state.locations.deinit(a);
    defer state.symbols.deinit(a);
    defer state.pending.deinit(a);
    for (0..2) |pass| {
        state.pass = @intCast(pass);
        state.pc = 0xe000;
        state.length = 0;
        state.first = null;
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_no: usize = 0;
        while (lines.next()) |text| {
            line_no += 1;
            state.line_number = line_no;
            diag.focus(source, lex.code(text));
            const line = parser.parse(text) catch |err| {
                diag.reason = @errorName(err);
                return err;
            };
            const before = state.pc;
            state.line(line) catch |err| return err;
            if (pass == 1 and state.pc > before) {
                var span: Diagnostic = .{};
                span.focus(source, lex.code(text));
                try state.locations.append(a, .{ .address = @intCast(before), .length = state.pc - before, .line = span.line, .column = span.column, .source = lex.code(text) });
            }
        }
        if (pass == 0) {
            while (state.pending.items.len > 0) {
                var progress = false;
                var k: usize = 0;
                while (k < state.pending.items.len) {
                    const sym = state.pending.items[k];
                    const value = state.value(sym.expression) catch |err| switch (err) {
                        error.UndefinedSymbol => {
                            k += 1;
                            continue;
                        },
                        else => return err,
                    };
                    _ = state.pending.orderedRemove(k);
                    try state.symbol(sym.name, value);
                    progress = true;
                }
                if (!progress) {
                    return state.unresolved();
                }
            }
        }
    }
    const entry: i64 = if (state.entry) |e| try state.value(e) else @intCast(state.first orelse return error.NoEntry);
    if (entry < 0xe000 or entry >= 0xe000 + state.length or @mod(entry, 2) != 0) return error.BadEntry;
    const image = try rom.pack(a, state.bytes[0..state.length], @intCast(entry - 0xe000));
    errdefer a.free(image);
    const symbols = try a.dupe(Symbol, state.symbols.items);
    errdefer a.free(symbols);
    return .{ .image = image, .symbols = symbols, .locations = try state.locations.toOwnedSlice(a), .allocator = a };
}
test "golden bytes forward labels and deterministic output" {
    const a = std.testing.allocator;
    var d: Diagnostic = .{};
    const source = ".entry start\n.equ value, 0x1234\nstart: ldi r1, value\nB.AL end\n.word 0xffff\nend: HALT\n";
    const r = try assemble(a, source, &d);
    defer r.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0, 0x22, 0x34, 0x12, 1, 0xd0, 0xff, 0xff, 1, 0 }, r.image[32..]);
    const r2 = try assemble(a, source, &d);
    defer r2.deinit();
    try std.testing.expectEqualSlices(u8, r.image, r2.image);
}
test "directives expressions and negative diagnostics" {
    const a = std.testing.allocator;
    var d: Diagnostic = .{};
    const r = try assemble(a, ".byte 0b10, 255\n.ascii \"a;:\\n\"\n.align 2\n.org 0xe010\n.entry x\nx: HALT\n.word x - 2\n.fill 2, 7", &d);
    defer r.deinit();
    try std.testing.expectEqual(16, (try rom.parse(r.image)).entry);
    for ([_][]const u8{ "LDI R8, 0", "LDI R0, 65536", "LDW R0, [R1 + 32]", ".org 0xe010\n.org 0xe000", "B.AL missing", "x: NOP\nx: HALT", "B.AL 0xe200", ".byte 0\nHALT", ".ascii \"bad", ".align 3" }) |s| {
        if (assemble(a, s, &d)) |bad| {
            bad.deinit();
            return error.ExpectedFailure;
        } else |_| {
            try std.testing.expect(d.line > 0);
        }
    }
}
test "forward constants depend on forward labels or constants and cycles reject" {
    const a = std.testing.allocator;
    var d: Diagnostic = .{};
    const r = try assemble(a, ".equ here, later - 2\n.equ next, end + 2\n.equ end, 0xe000\nLDI R0, here\nlater: HALT", &d);
    defer r.deinit();
    try std.testing.expectEqual(0xe002, std.mem.readInt(u16, r.image[34..36], .little));
    try std.testing.expectError(error.CyclicConstant, assemble(a, ".equ a, b\n.equ b, a\nHALT", &d));
    try std.testing.expectEqual(1, d.line);
}
test "diagnostics point to actual entry expression and invalid operand spans" {
    const a = std.testing.allocator;
    var d: Diagnostic = .{};
    try std.testing.expectError(error.UndefinedSymbol, assemble(a, "  .entry missing\nHALT\n", &d));
    try std.testing.expectEqual(1, d.line);
    try std.testing.expectEqual(10, d.column);
    try std.testing.expectEqualStrings("missing", d.token);
    try std.testing.expectEqualStrings("UndefinedSymbol", d.code);
    try std.testing.expectError(error.ExpectedRegister, assemble(a, "  LDI R8, 2", &d));
    try std.testing.expectEqual(7, d.column);
    try std.testing.expectEqual(2, d.length);
    try std.testing.expectError(error.Width, assemble(a, "LDI R0, 9223372036854775807 + 1", &d));
    try std.testing.expectEqual(9, d.column);
}
pub fn writeListing(w: *std.Io.Writer, result: Result) !void {
    for (result.locations) |loc| {
        var offset: usize = 0;
        while (offset < loc.length) : (offset += 8) {
            const size = @min(8, loc.length - offset);
            const payload_offset = loc.address - 0xe000 + offset;
            try w.print("{x:0>4}: ", .{loc.address + offset});
            for (0..8) |k| {
                if (k < size) try w.print("{x:0>2} ", .{result.image[32 + payload_offset + k]}) else try w.writeAll("   ");
            }
            if (offset == 0) try w.print("{d}:{d} {s}", .{ loc.line, loc.column, loc.source });
            try w.writeByte('\n');
        }
    }
}
test "listing contains addresses bytes and original source" {
    const a = std.testing.allocator;
    var d: Diagnostic = .{};
    const r = try assemble(a, "  LDI R1, 0x1234\nHALT", &d);
    defer r.deinit();
    var text: std.Io.Writer.Allocating = .init(a);
    defer text.deinit();
    try writeListing(&text.writer, r);
    try std.testing.expect(std.mem.indexOf(u8, text.written(), "e000: 00 22 34 12") != null);
    try std.testing.expect(std.mem.indexOf(u8, text.written(), "1:3 LDI R1") != null);
}

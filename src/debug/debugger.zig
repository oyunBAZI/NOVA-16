const std = @import("std");
const Machine = @import("../core/machine.zig").Machine;
const Bus = @import("../core/bus.zig").Bus;
const disasm = @import("disasm.zig");
const asm16 = @import("../asm/assembler.zig");
pub const Debugger = struct {
    machine: *Machine,
    recorder: @import("history.zig").Recorder = .{},
    variables: []const @import("symbols.zig").Variable = &.{},
    sources: []const @import("symbols.zig").Source = &.{},
    breaks: [32768]bool = @splat(false),
    watches: [65536]bool = @splat(false),
    symbols: []const asm16.Symbol = &.{},
    pub fn deinit(self: *Debugger) void {
        self.recorder.deinit();
    }
    pub fn clearHistory(self: *Debugger) void {
        self.recorder.clear();
    }
    pub const Action = union(enum) { none, quit, saveframe: []const u8, savesnap: []const u8, loadsnap: []const u8 };
    pub fn command(self: *Debugger, line: []const u8, out: *std.Io.Writer) !Action {
        if (line.len > 4096) return error.CommandTooLong;
        var args = std.mem.tokenizeAny(u8, line, " \t\r\n");
        const cmd = args.next() orelse return .none;
        var tokens: [3][]const u8 = undefined;
        var count: usize = 0;
        while (args.next()) |arg| {
            if (count == 3) return error.TooManyArguments;
            tokens[count] = arg;
            count += 1;
        }
        if (eq(cmd, "help")) {
            try arity(count, 0);
            try out.writeAll("help regs step [n] continue [budget] break ADDRESS delete ADDRESS\nwatch ADDRESS unwatch ADDRESS disasm ADDRESS COUNT mem ADDRESS LENGTH\nstack COUNT reset saveframe PATH savesnap PATH loadsnap PATH quit\nframe [n] input MASK devices trace [n] history [capacity] reverse source [ADDRESS] next [budget] symbols vars var NAME\n");
        } else if (eq(cmd, "regs")) {
            try arity(count, 0);
            const c = &self.machine.cpu;
            for (c.r, 0..) |r, k| try out.print("R{d}={x:0>4} ", .{ k, r });
            try out.print("\nPC={x:0>4} SP={x:0>4} Z={d} N={d} C={d} V={d} halted={any} paused={any} retired={d}\n", .{ c.pc, c.sp, c.flags & 1, (c.flags >> 1) & 1, (c.flags >> 2) & 1, (c.flags >> 3) & 1, c.halted, c.paused, c.retired });
            try self.status(out);
        } else if (eq(cmd, "step") or eq(cmd, "continue")) {
            if (count > 1) return error.ArgumentCount;
            const budget = if (count == 1) try number(tokens[0], 1_000_000) else if (eq(cmd, "step")) @as(u64, 1) else 1_000_000;
            self.machine.cpu.paused = false;
            for (0..budget) |_| {
                const c = &self.machine.cpu;
                if (c.halted or c.paused or c.trap != null) break;
                if (!try self.runOne(out, eq(cmd, "continue"))) break;
            }
            try self.status(out);
        } else if (eq(cmd, "vars") or eq(cmd, "var")) {
            if ((eq(cmd, "vars") and count != 0) or (eq(cmd, "var") and count != 1)) return error.ArgumentCount;
            var found = false;
            for (self.variables) |variable| {
                if (self.machine.cpu.pc < variable.scope_start or self.machine.cpu.pc >= variable.scope_end) continue;
                if (count == 1 and !std.mem.eql(u8, tokens[0], variable.name)) continue;
                found = true;
                try out.print("{s}:{s}=", .{ variable.name, variable.type_name });
                if (variable.constant) |value| try out.print("{d}", .{value}) else {
                    const location = @as(u32, variable.address) + (if (variable.frame_relative) @as(u32, self.machine.cpu.r[7]) else 0);
                    if (location + @as(u32, variable.words) * 2 > 0x8000 or (variable.frame_relative and location < 0x4000)) return error.InvalidVariableFrame;
                    for (0..@min(variable.words, 16)) |index| {
                        const low = try self.machine.bus.peek(@intCast(location + index * 2));
                        const high = try self.machine.bus.peek(@intCast(location + index * 2 + 1));
                        const value = @as(u16, low) | (@as(u16, high) << 8);
                        if (index > 0) try out.writeByte(',');
                        if (variable.signed) try out.print("{d}", .{@as(i16, @bitCast(value))}) else try out.print("{d}", .{value});
                    }
                    if (variable.words > 16) try out.writeAll(",...");
                }
                try out.writeByte('\n');
            }
            if (!found) return error.VariableNotInScope;
        } else if (eq(cmd, "symbols")) {
            try arity(count, 0);
            for (self.symbols) |sym| try out.print("{s}={x}\n", .{ sym.name, sym.value });
        } else if (eq(cmd, "next")) {
            if (count > 1) return error.ArgumentCount;
            const budget = if (count == 1) try number(tokens[0], 1_000_000) else 100_000;
            const origin = self.sourceAt(self.machine.cpu.pc) orelse return error.NoSourceLocation;
            self.machine.cpu.paused = false;
            for (0..budget) |_| {
                if (!try self.runOne(out, false)) break;
                if (self.breaks[self.machine.cpu.pc / 2]) break;
                const current = self.sourceAt(self.machine.cpu.pc) orelse break;
                if (current.line != origin.line or !std.mem.eql(u8, current.file, origin.file)) break;
            }
            try self.status(out);
        } else if (eq(cmd, "input")) {
            try arity(count, 1);
            self.machine.bus.input.inject(@intCast(try number(tokens[0], 255)));
        } else if (eq(cmd, "devices")) {
            try arity(count, 0);
            const b = &self.machine.bus;
            try out.print("held={x:0>2} pressed={x:0>2} frame={d} vblank={any} enabled={any}\n", .{ b.input.held, b.input.pressed, b.frame, b.vblank, b.enabled });
            for (0..16) |k| try out.print("palette {d}: {x:0>2}{x:0>2}{x:0>2}\n", .{ k, b.palette[k * 3], b.palette[k * 3 + 1], b.palette[k * 3 + 2] });
        } else if (eq(cmd, "frame")) {
            if (count > 1) return error.ArgumentCount;
            const frames = if (count == 1) try number(tokens[0], 1000) else 1;
            self.machine.cpu.paused = false;
            for (0..frames) |_| {
                if (self.machine.cpu.halted or self.machine.cpu.paused or self.machine.cpu.trap != null) break;
                self.machine.bus.input.inject(self.machine.bus.input.held);
                var running = true;
                for (0..@import("../arch/isa.zig").frame_budget) |_| if (!try self.runOne(out, true)) {
                    running = false;
                    break;
                };
                self.machine.bus.frame +%= 1;
                self.machine.bus.vblank = true;
                if (!running) break;
            }
            try self.status(out);
        } else if (eq(cmd, "trace")) {
            if (count > 1) return error.ArgumentCount;
            try self.recorder.print(out, @intCast(if (count == 1) try number(tokens[0], 128) else 16));
        } else if (eq(cmd, "history")) {
            if (count > 1) return error.ArgumentCount;
            if (count == 1) try self.recorder.configure(@intCast(try number(tokens[0], 32)));
            try out.print("history={d} trace={d}\n", .{ self.recorder.undo_count, self.recorder.trace_count });
        } else if (eq(cmd, "reverse")) {
            try arity(count, 0);
            try self.recorder.reverse(self.machine);
            try self.status(out);
        } else if (eq(cmd, "source")) {
            if (count > 1) return error.ArgumentCount;
            const addr = if (count == 0) self.machine.cpu.pc else try self.address(tokens[0]);
            for (self.sources) |loc| if (addr >= loc.address and addr - loc.address < loc.length) {
                try out.print("{s}:{d}:{d}\n", .{ loc.file, loc.line, loc.column });
            };
        } else if (eq(cmd, "break") or eq(cmd, "delete")) {
            try arity(count, 1);
            const addr: u16 = try self.sourceAddress(tokens[0]);
            if (!@import("../arch/isa.zig").executable(addr)) return error.InvalidBreakpoint;
            self.breaks[addr / 2] = eq(cmd, "break");
        } else if (eq(cmd, "watch") or eq(cmd, "unwatch")) {
            try arity(count, 1);
            const addr: u16 = try self.address(tokens[0]);
            try Bus.validate(addr, true);
            self.watches[addr] = eq(cmd, "watch");
        } else if (eq(cmd, "mem")) {
            try arity(count, 2);
            const addr = @as(u64, try self.address(tokens[0]));
            const len = try number(tokens[1], 4096);
            if (addr + len > 65536) return error.AddressRange;
            var k: u64 = 0;
            while (k < len) : (k += 16) {
                const row = @min(16, len - k);
                try out.print("{x:0>4}: ", .{addr + k});
                for (0..16) |j| {
                    if (j < row) {
                        if (self.machine.bus.peek(@intCast(addr + k + j))) |v| try out.print("{x:0>2} ", .{v}) else |_| try out.writeAll("?? ");
                    } else try out.writeAll("   ");
                }
                try out.writeAll(" |");
                for (0..row) |j| {
                    const v = self.machine.bus.peek(@intCast(addr + k + j)) catch 0;
                    try out.writeByte(if (v >= 32 and v <= 126) v else '.');
                }
                try out.writeAll("|\n");
            }
        } else if (eq(cmd, "disasm")) {
            try arity(count, 2);
            var addr = @as(u64, try self.address(tokens[0]));
            const len = try number(tokens[1], 4096);
            if (addr & 1 != 0) return error.Unaligned;
            for (0..len) |_| {
                if (addr > 65534) break;
                for (self.symbols) |s| if (s.value == addr) {
                    try out.print("{s}:\n", .{s.name});
                };
                const low = try self.machine.bus.peek(@intCast(addr));
                const high = try self.machine.bus.peek(@intCast(addr + 1));
                const w = @as(u16, low) | (@as(u16, high) << 8);
                var imm: ?u16 = null;
                if (addr <= 65532) {
                    const l = self.machine.bus.peek(@intCast(addr + 2)) catch null;
                    const h = self.machine.bus.peek(@intCast(addr + 3)) catch null;
                    if (l != null and h != null) imm = @as(u16, l.?) | (@as(u16, h.?) << 8);
                }
                try out.print("{x:0>4}: ", .{addr});
                addr += try disasm.instruction(out, w, imm, @intCast(addr));
                try out.writeByte('\n');
            }
        } else if (eq(cmd, "stack")) {
            try arity(count, 1);
            const len = try number(tokens[0], 1024);
            const c = &self.machine.cpu;
            for (0..@min(len, c.depth)) |k| {
                const addr: u16 = @intCast(@as(u32, c.sp) + k * 2);
                try out.print("{x:0>4}: {x:0>4}\n", .{ addr, try self.machine.bus.read16(addr) });
            }
            if (c.depth == 0) try out.writeAll("empty stack\n");
        } else if (eq(cmd, "reset")) {
            try arity(count, 0);
            self.machine.reset();
            self.clearHistory();
            try self.status(out);
        } else if (eq(cmd, "saveframe")) {
            try arity(count, 1);
            return .{ .saveframe = tokens[0] };
        } else if (eq(cmd, "savesnap") or eq(cmd, "loadsnap")) {
            try arity(count, 1);
            return if (eq(cmd, "savesnap")) .{ .savesnap = tokens[0] } else .{ .loadsnap = tokens[0] };
        } else if (eq(cmd, "quit")) {
            try arity(count, 0);
            return .quit;
        } else return error.UnknownCommand;
        return .none;
    }
    fn address(self: *const Debugger, text: []const u8) !u16 {
        for (self.symbols) |sym| if (std.mem.eql(u8, text, sym.name)) {
            if (sym.value < 0 or sym.value > 65535) return error.AddressRange;
            return @intCast(sym.value);
        };
        return @intCast(try number(text, 65535));
    }
    fn sourceAt(self: *const Debugger, pc: u16) ?@import("symbols.zig").Source {
        for (self.sources) |loc| if (pc >= loc.address and pc - loc.address < loc.length) return loc;
        return null;
    }
    fn sourceAddress(self: *Debugger, text: []const u8) !u16 {
        const colon = std.mem.lastIndexOfScalar(u8, text, ':') orelse return self.address(text);
        const line = try number(text[colon + 1 ..], 32768);
        for (self.sources) |loc| if (std.mem.eql(u8, loc.file, text[0..colon]) and loc.line == line) {
            const addr: u16 = @intCast(loc.address);
            const word = try self.machine.bus.fetch(addr);
            _ = try @import("../arch/isa.zig").decode(word);
            return addr;
        };
        return error.SourceLocationNotFound;
    }
    fn runOne(self: *Debugger, out: *std.Io.Writer, respect_break: bool) !bool {
        const c = &self.machine.cpu;
        if (c.halted or c.paused or c.trap != null) return false;
        if (respect_break and c.pc & 1 == 0 and self.breaks[c.pc / 2]) {
            try out.print("breakpoint before {x:0>4}\n", .{c.pc});
            return false;
        }
        self.recorder.step(self.machine);
        var hit = false;
        for (self.machine.bus.writes[0..self.machine.bus.write_count]) |event| if (self.watches[event.address]) {
            try out.print("watch {x:0>4}: {x:0>2} -> {x:0>2}\n", .{ event.address, event.old, event.new });
            hit = true;
        };
        return !hit and !c.halted and !c.paused and c.trap == null;
    }
    fn status(self: *Debugger, out: *std.Io.Writer) !void {
        const c = &self.machine.cpu;
        if (c.trap) |t| {
            try out.print("trap {s} pc={x:0>4} {s} address={d} opcode={x:0>4}\n", .{ @errorName(t.kind), t.pc, @tagName(t.access), t.address, t.instruction });
            const immediate: ?u16 = if (t.pc <= 65532) blk: {
                const lo = self.machine.bus.peek(t.pc + 2) catch break :blk null;
                const hi = self.machine.bus.peek(t.pc + 3) catch break :blk null;
                break :blk @as(u16, lo) | (@as(u16, hi) << 8);
            } else null;
            _ = try disasm.instruction(out, t.instruction, immediate, t.pc);
            try out.writeByte('\n');
        } else try out.print("PC={x:0>4} {s}\n", .{ c.pc, if (c.halted) "HALT" else if (c.paused) "BRK" else "ready" });
        if (c.paused and self.sourceAt(c.pc) != null and std.mem.eql(u8, self.sourceAt(c.pc).?.file, "<n16-runtime>")) {
            const code = try self.machine.bus.read16(0xf0);
            const line = try self.machine.bus.read16(0xf2);
            if (code >= 1 and code <= 3 and line != 0) {
                for (self.sources) |loc| if (!std.mem.eql(u8, loc.file, "<n16-runtime>")) {
                    try out.print("guest error {d} at {s}:{d}\n", .{ code, loc.file, line });
                    break;
                };
            }
        }
        if (self.sourceAt(if (c.trap) |t| t.pc else c.pc)) |loc| try out.print("at {s}:{d}:{d}\n", .{ loc.file, loc.line, loc.column });
    }
};
fn eq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}
fn arity(actual: usize, expected: usize) !void {
    if (actual != expected) return error.ArgumentCount;
}
fn number(s: []const u8, max: u64) !u64 {
    const v = std.fmt.parseInt(u64, s, 0) catch return error.InvalidNumber;
    if (v > max) return error.Limit;
    return v;
}
test "scripted break-before-execute watch BRK resume and reset" {
    const a = std.testing.allocator;
    var diag: asm16.Diagnostic = .{};
    const r = try asm16.assemble(a, "LDI R0, 0xc000\nLDI R1, 42\nSTB R1, [R0]\nBRK\nPUSH R1\nPOP R2\nHALT", &diag);
    defer r.deinit();
    var m: Machine = .{};
    try m.load(r.image);
    var d: Debugger = .{ .machine = &m };
    var output: std.Io.Writer.Allocating = .init(a);
    defer output.deinit();
    _ = try d.command("break 0xe004", &output.writer);
    _ = try d.command("continue 100", &output.writer);
    try std.testing.expectEqual(1, m.cpu.retired);
    _ = try d.command("step", &output.writer);
    try std.testing.expectEqual(2, m.cpu.retired);
    _ = try d.command("watch 0xc000", &output.writer);
    _ = try d.command("continue 100", &output.writer);
    try std.testing.expectEqual(42, m.bus.bytes[0xc000]);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "00 -> 2a") != null);
    _ = try d.command("continue", &output.writer);
    try std.testing.expect(m.cpu.paused);
    try std.testing.expectEqual(0xe00c, m.cpu.pc);
    _ = try d.command("step", &output.writer);
    _ = try d.command("stack 4", &output.writer);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "002a") != null);
    _ = try d.command("continue", &output.writer);
    try std.testing.expect(m.cpu.halted);
    try std.testing.expectEqual(42, m.cpu.r[2]);
    _ = try d.command("reset", &output.writer);
    try std.testing.expectEqual(0, m.cpu.retired);
    try std.testing.expectError(error.InvalidNumber, d.command("step nope", &output.writer));
    try std.testing.expectError(error.AddressRange, d.command("mem 65535 2", &output.writer));
}
test "frame input trace reverse snapshots and nonacknowledging devices" {
    const a = std.testing.allocator;
    var diag: asm16.Diagnostic = .{};
    const r = try asm16.assemble(a, "LDI R0, 0xd800\nLDB R1, [R0]\nLDI R2, 0xc000\nSTB R1, [R2]\nB.AL 0xe004", &diag);
    defer r.deinit();
    var m: Machine = .{};
    try m.load(r.image);
    var d: Debugger = .{ .machine = &m, .recorder = .{ .allocator = a } };
    defer d.deinit();
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    _ = try d.command("history 8", &out.writer);
    _ = try d.command("input 16", &out.writer);
    _ = try d.command("step 4", &out.writer);
    try std.testing.expectEqual(16, m.bus.bytes[0xc000]);
    _ = try d.command("trace 4", &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "[c000]:00->10") != null);
    _ = try d.command("reverse", &out.writer);
    try std.testing.expectEqual(0, m.bus.bytes[0xc000]);
    _ = try d.command("step", &out.writer);
    try std.testing.expectEqual(16, m.bus.bytes[0xc000]);
    _ = try d.command("devices", &out.writer);
    try std.testing.expectEqual(16, m.bus.input.pressed);
    _ = try d.command("frame 1", &out.writer);
    try std.testing.expectEqual(1, m.bus.frame);
    const snapshot = @import("../core/snapshot.zig");
    const state = try snapshot.encode(a, &m);
    defer a.free(state);
    _ = try d.command("input 32", &out.writer);
    _ = try d.command("frame 2", &out.writer);
    const expected = try snapshot.encode(a, &m);
    defer a.free(expected);
    try snapshot.restore(&m, state, m.checksum);
    d.clearHistory();
    _ = try d.command("input 32", &out.writer);
    _ = try d.command("frame 2", &out.writer);
    const actual = try snapshot.encode(a, &m);
    defer a.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
    _ = try d.command("break 0xe004", &out.writer);
    m.cpu.pc = 0xe004;
    const before = m.cpu.retired;
    _ = try d.command("frame", &out.writer);
    try std.testing.expectEqual(before, m.cpu.retired);
}

test "source commands reporting and malformed source locations have bounded behavior" {
    const a = std.testing.allocator;
    var m: Machine = .{};
    const symbols = [_]asm16.Symbol{.{ .name = "entry", .value = 0xe000 }};
    const sources = [_]@import("symbols.zig").Source{.{ .file = "main.asm", .line = 3, .column = 1, .address = 0xe000, .length = 2 }};
    var d: Debugger = .{ .machine = &m, .symbols = &symbols, .sources = &sources };
    defer d.deinit();
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    for ([_][]const u8{ "help", "regs", "source", "symbols", "break main.asm:3", "delete main.asm:3", "disasm entry 1", "mem entry 2", "next 1" }) |cmd| _ = try d.command(cmd, &out.writer);
    try std.testing.expectError(error.SourceLocationNotFound, d.command("break main.asm:2", &out.writer));
    try std.testing.expectError(error.InvalidNumber, d.command("break main.asm:no", &out.writer));
    _ = try d.command("saveframe screen.ppm", &out.writer);
    _ = try d.command("savesnap state.n16s", &out.writer);
    _ = try d.command("loadsnap state.n16s", &out.writer);
    _ = try d.command("quit", &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "main.asm:3:1") != null);
}

const std = @import("std");
const Machine = @import("../core/machine.zig").Machine;
const Bus = @import("../core/bus.zig").Bus;
const disasm = @import("disasm.zig");
const asm16 = @import("../asm/assembler.zig");
pub const Debugger = struct {
    machine: *Machine,
    breaks: [32768]bool = @splat(false),
    watches: [65536]bool = @splat(false),
    symbols: []const asm16.Symbol = &.{},
    pub const Action = union(enum) { none, quit, saveframe: []const u8 };
    pub fn command(self: *Debugger, line: []const u8, out: *std.Io.Writer) !Action {
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
            try out.writeAll("help regs step [n] continue [budget] break ADDRESS delete ADDRESS\nwatch ADDRESS unwatch ADDRESS disasm ADDRESS COUNT mem ADDRESS LENGTH\nstack COUNT reset saveframe PATH quit\n");
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
                if (eq(cmd, "continue") and c.pc & 1 == 0 and self.breaks[c.pc / 2]) {
                    try out.print("breakpoint before {x:0>4}\n", .{c.pc});
                    break;
                }
                self.machine.step();
                var hit = false;
                for (self.machine.bus.writes[0..self.machine.bus.write_count]) |w| if (self.watches[w.address]) {
                    try out.print("watch {x:0>4}: {x:0>2} -> {x:0>2}\n", .{ w.address, w.old, w.new });
                    hit = true;
                };
                if (hit) break;
            }
            try self.status(out);
        } else if (eq(cmd, "break") or eq(cmd, "delete")) {
            try arity(count, 1);
            const addr: u16 = @intCast(try number(tokens[0], 65535));
            if (!@import("../arch/isa.zig").executable(addr)) return error.InvalidBreakpoint;
            self.breaks[addr / 2] = eq(cmd, "break");
        } else if (eq(cmd, "watch") or eq(cmd, "unwatch")) {
            try arity(count, 1);
            const addr: u16 = @intCast(try number(tokens[0], 65535));
            try Bus.validate(addr, true);
            self.watches[addr] = eq(cmd, "watch");
        } else if (eq(cmd, "mem")) {
            try arity(count, 2);
            const addr = try number(tokens[0], 65535);
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
            var addr = try number(tokens[0], 65535);
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
            try self.status(out);
        } else if (eq(cmd, "saveframe")) {
            try arity(count, 1);
            return .{ .saveframe = tokens[0] };
        } else if (eq(cmd, "quit")) {
            try arity(count, 0);
            return .quit;
        } else return error.UnknownCommand;
        return .none;
    }
    fn status(self: *Debugger, out: *std.Io.Writer) !void {
        const c = &self.machine.cpu;
        if (c.trap) |t| try out.print("trap {s} pc={x:0>4} {s} address={x:0>4}\n", .{ @errorName(t.kind), t.pc, @tagName(t.access), t.address }) else try out.print("PC={x:0>4} {s}\n", .{ c.pc, if (c.halted) "HALT" else if (c.paused) "BRK" else "ready" });
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

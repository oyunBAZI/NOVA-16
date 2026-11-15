//! Host-only Workbench model. Observation never acknowledges guest MMIO.
const std = @import("std");
const Machine = @import("../core/machine.zig").Machine;
const Debugger = @import("../debug/debugger.zig").Debugger;
const snapshot = @import("../core/snapshot.zig");
pub const Request = struct {
    version: u8 = 1,
    op: enum { observe, command, frame, replay_frame, snapshot, restore } = .observe,
    command: []const u8 = "",
    address: u16 = 0,
    length: u16 = 256,
    data: []const u8 = "",
};
pub const Session = struct {
    debugger: *Debugger,
    pcm: [800]i16 = @splat(0),
    pcm_valid: bool = false,
    stopped: bool = true,
    pub fn apply(self: *Session, a: std.mem.Allocator, request: Request, out: *std.Io.Writer) !?[]u8 {
        if (request.version != 1) return error.ProtocolVersion;
        if (request.length > 256 or @as(u32, request.address) + request.length > 65536) return error.MemoryRange;
        const d = self.debugger;
        const m = d.machine;
        switch (request.op) {
            .observe => {},
            .snapshot => return try snapshot.encodeChecked(a, m),
            .restore => {
                if (request.data.len > snapshot.v2_file_size * 2 or request.data.len & 1 != 0) return error.SnapshotLength;
                const bytes = try a.alloc(u8, request.data.len / 2);
                defer a.free(bytes);
                _ = try std.fmt.hexToBytes(bytes, request.data);
                try snapshot.restore(m, bytes, m.checksum);
                d.clearHistory();
                self.pcm_valid = false;
                self.stopped = true;
            },
            .frame => try self.frame(out),
            .replay_frame => {
                if (m.bus.profile == .v1 and (m.cpu.halted or m.cpu.paused or m.cpu.trap != null)) return null;
                d.recorder.beginGroup(m);
                defer d.recorder.endGroup();
                self.pcm_valid = false;
                m.injectInput(m.bus.input.held);
                const remaining: u64 = if (m.bus.profile == .v2) 20000 - m.slots % 20000 else 20000;
                for (0..@as(usize, @intCast(remaining))) |_| {
                    if (m.cpu.halted or m.cpu.paused or m.cpu.trap != null) {
                        if (m.bus.profile == .v1) break;
                        if (!m.transition(false, &self.pcm)) break;
                    } else d.recorder.stepAudio(m, &self.pcm);
                }
                if (m.bus.profile == .v1) {
                    m.bus.frame +%= 1;
                    m.bus.vblank = true;
                } else self.pcm_valid = m.slots % 20000 == 0;
                self.stopped = m.cpu.halted or m.cpu.paused or m.cpu.trap != null;
            },
            .command => {
                if (request.command.len > 256) return error.CommandTooLong;
                var tokens = std.mem.tokenizeAny(u8, request.command, " \t\r\n");
                const cmd = tokens.next() orelse return error.EmptyCommand;
                var allowed = false;
                for ([_][]const u8{ "help", "regs", "step", "continue", "next", "break", "delete", "watch", "unwatch", "disasm", "mem", "stack", "reset", "input", "devices", "trace", "history", "reverse", "source", "symbols", "vars", "var" }) |name| {
                    if (std.mem.eql(u8, cmd, name)) allowed = true;
                }
                if (!allowed) return error.CommandDenied;
                const execute = std.mem.eql(u8, cmd, "step") or std.mem.eql(u8, cmd, "continue") or std.mem.eql(u8, cmd, "next");
                // A protocol request can never run an unbounded/default million-step job.
                var buffer: [280]u8 = undefined;
                var command = request.command;
                if (execute) {
                    if (tokens.next()) |text| {
                        const budget = std.fmt.parseInt(u32, text, 0) catch return error.InvalidNumber;
                        if (budget > 20000) return error.ExecutionLimit;
                        if (tokens.next() != null) return error.ArgumentCount;
                    } else if (!std.mem.eql(u8, cmd, "step")) command = try std.fmt.bufPrint(&buffer, "{s} 20000", .{cmd});
                }
                _ = try d.command(command, out);
                if (execute or std.mem.eql(u8, cmd, "reset") or std.mem.eql(u8, cmd, "reverse")) self.pcm_valid = false;
                self.stopped = true;
            },
        }
        return null;
    }
    /// Rewind treats a frame as one action, avoiding 20,000 whole-machine copies.
    /// Break/watch checks still use the existing instruction debugger.
    fn frame(self: *Session, out: *std.Io.Writer) !void {
        const d = self.debugger;
        const m = d.machine;
        self.stopped = false;
        self.pcm_valid = false;
        if (m.bus.profile == .v1 and (m.cpu.halted or m.cpu.paused or m.cpu.trap != null)) {
            self.stopped = true;
            return;
        }
        d.recorder.beginGroup(m);
        defer d.recorder.endGroup();
        m.injectInput(m.bus.input.held);
        if (m.bus.profile == .v1) {
            for (0..20000) |_| {
                if (!try d.runOneAudio(out, true, null)) {
                    self.stopped = true;
                    break;
                }
            }
            m.bus.frame +%= 1;
            m.bus.vblank = true;
        } else {
            const before_slots = m.slots;
            const remaining = 20000 - m.slots % 20000;
            for (0..@as(usize, @intCast(remaining))) |_| {
                if (m.cpu.halted or m.cpu.paused or m.cpu.trap != null) {
                    self.stopped = true;
                    if (!m.transition(false, &self.pcm)) break;
                } else if (!try d.runOneAudio(out, true, &self.pcm)) {
                    self.stopped = true;
                    // Guest stops still finish a frame's device time. Debugger
                    // break/watch stops retain their precise partial-frame slot.
                    if (!m.cpu.halted and !m.cpu.paused and m.cpu.trap == null) break;
                }
            }
            self.pcm_valid = m.slots > before_slots and m.slots % 20000 == 0;
        }
    }
    pub fn writeObservation(self: *const Session, a: std.mem.Allocator, w: *std.Io.Writer, request: Request) !void {
        const d = self.debugger;
        const m = d.machine;
        try w.writeAll(",\"state\":");
        var state_text: std.Io.Writer.Allocating = .init(a);
        defer state_text.deinit();
        try @import("../cli/state.zig").json(&state_text.writer, m);
        try w.writeAll(std.mem.trimEnd(u8, state_text.written(), "\n"));
        try w.print(",\"profile\":{d},\"stopped\":{s},\"history_count\":{d},\"history_capacity\":{d},\"display_enabled\":{s},\"vram\":\"", .{ @backingInt(m.bus.profile), if (self.stopped) "true" else "false", d.recorder.undo_count, d.recorder.capacity(), if (m.bus.enabled) "true" else "false" });
        try writeHex(w, m.bus.bytes[0xc000..0xd800]);
        try w.writeAll("\",\"palette\":");
        try std.json.Stringify.value(m.bus.palette, .{}, w);
        try w.writeAll(",\"source\":");
        try std.json.Stringify.value(d.sourceAt(if (m.cpu.trap) |t| t.pc else m.cpu.pc), .{}, w);
        try w.writeAll(",\"breakpoints\":[");
        var comma = false;
        for (d.breaks, 0..) |active, i| if (active) {
            if (comma) try w.writeByte(',');
            try w.print("{d}", .{i * 2});
            comma = true;
        };
        try w.print("],\"memory_address\":{d},\"memory\":[", .{request.address});
        for (0..@min(request.length, 256)) |i| {
            if (i > 0) try w.writeByte(',');
            const addr = @as(u32, request.address) + i;
            const byte: ?u8 = if (addr > 65535) null else m.inspect(@intCast(addr)) catch null;
            try std.json.Stringify.value(byte, .{}, w);
        }
        try w.print("],\"input_held\":{d},\"input_pressed\":{d},\"audio\":", .{ m.bus.input.held, m.bus.input.pressed });
        if (m.bus.profile == .v2) {
            try std.json.Stringify.value(.{ .sample_rate = @as(u32, 48000), .enabled = m.bus.audio.enabled, .gain = m.bus.audio.gain, .voices = m.bus.audio.voices, .completed_frame = self.pcm_valid, .pcm = if (self.pcm_valid) self.pcm[0..] else m.bus.audio.pcm[0..m.bus.audio.prefix] }, .{}, w);
        } else try w.writeAll("null");
        var text: std.Io.Writer.Allocating = .init(a);
        defer text.deinit();
        var addr: u32 = m.cpu.pc;
        for (0..10) |_| {
            if (addr > 65532) break;
            const low = m.inspect(@intCast(addr)) catch break;
            const high = m.inspect(@intCast(addr + 1)) catch break;
            const lo = m.inspect(@intCast(addr + 2)) catch break;
            const hi = m.inspect(@intCast(addr + 3)) catch break;
            try text.writer.print("{x:0>4}  ", .{addr});
            addr += try @import("../debug/disasm.zig").instructionProfile(&text.writer, @as(u16, low) | (@as(u16, high) << 8), @as(u16, lo) | (@as(u16, hi) << 8), @intCast(addr), m.bus.profile);
            try text.writer.writeByte('\n');
        }
        try w.writeAll(",\"disassembly\":");
        try std.json.Stringify.value(text.written(), .{}, w);
    }
};
pub fn writeHex(w: *std.Io.Writer, bytes: []const u8) !void {
    const digits = "0123456789abcdef";
    for (bytes) |byte| try w.writeAll(&.{ digits[byte >> 4], digits[byte & 15] });
}

test "Workbench frame equals canonical V2, captures PCM, and reverses exactly" {
    const t = std.testing;
    const asm16 = @import("../asm/assembler.zig");
    var diag: asm16.Diagnostic = .{};
    const result = try asm16.assembleProfile(t.allocator, "HALT", &diag, .v2);
    defer result.deinit();
    var m: Machine = .{};
    try m.load(result.image);
    var reference = m;
    var d: Debugger = .{ .machine = &m, .recorder = .{ .allocator = t.allocator } };
    defer d.deinit();
    try d.recorder.configure(32);
    var session: Session = .{ .debugger = &d };
    var out: std.Io.Writer.Allocating = .init(t.allocator);
    defer out.deinit();
    var pcm: [800]i16 = undefined;
    _ = reference.frameAudio(0, std.math.maxInt(u64), &pcm);
    _ = try session.apply(t.allocator, .{ .op = .frame }, &out.writer);
    const before = try snapshot.encodeChecked(t.allocator, &reference);
    defer t.allocator.free(before);
    const after = try snapshot.encodeChecked(t.allocator, &m);
    defer t.allocator.free(after);
    try t.expectEqualSlices(u8, before, after);
    try t.expect(session.pcm_valid);
    try t.expectEqualSlices(i16, &pcm, &session.pcm);
    try t.expectEqual(1, d.recorder.undo_count);
    _ = try session.apply(t.allocator, .{ .op = .command, .command = "reverse" }, &out.writer);
    try t.expectEqual(0, m.slots);
    try t.expectEqual(0, m.cpu.retired);
}

test "Workbench observations and rejected requests are nonacknowledging and bounded" {
    const t = std.testing;
    var m: Machine = .{};
    m.injectInput(17);
    var d: Debugger = .{ .machine = &m };
    defer d.deinit();
    var session: Session = .{ .debugger = &d };
    var out: std.Io.Writer.Allocating = .init(t.allocator);
    defer out.deinit();
    try session.writeObservation(t.allocator, &out.writer, .{ .address = 0xd800 });
    try t.expectEqual(17, m.bus.input.pressed);
    try t.expectError(error.CommandDenied, session.apply(t.allocator, .{ .op = .command, .command = "savesnap /tmp/a" }, &out.writer));
    try t.expectError(error.ExecutionLimit, session.apply(t.allocator, .{ .op = .command, .command = "step 20001" }, &out.writer));
    try t.expectError(error.MemoryRange, session.apply(t.allocator, .{ .address = 65535, .length = 2 }, &out.writer));
    try t.expectError(error.ProtocolVersion, session.apply(t.allocator, .{ .version = 2 }, &out.writer));
    try t.expectEqual(0, m.cpu.retired);
}

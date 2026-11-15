const std = @import("std");
const Machine = @import("../core/machine.zig").Machine;
const Cpu = @import("../core/cpu.zig").Cpu;
const Timeline = @import("timeline.zig").Timeline;
const Write = @import("../core/bus.zig").Write;
pub const Trace = struct { irq_entry: ?u8 = null, profile: @import("../arch/isa.zig").Profile = .v1, slots: u64 = 0, before: Cpu, after: Cpu, writes: [6]Write, count: u3, word: u16, immediate: u16, length: u3 };
pub const Recorder = struct {
    allocator: std.mem.Allocator = std.heap.page_allocator,
    trace: [128]Trace = undefined,
    trace_next: usize = 0,
    trace_count: usize = 0,
    undo: ?[]Machine = null,
    timeline: ?Timeline = null,
    undo_next: usize = 0,
    undo_count: usize = 0,
    grouped: bool = false,
    /// A bounded host action can share one exact undo boundary. Traces remain
    /// per instruction; the existing debugger retains instruction undo by default.
    pub fn beginGroup(self: *Recorder, m: *const Machine) void {
        std.debug.assert(!self.grouped);
        self.capture(m);
        if (self.timeline) |*timeline| timeline.beginGroup();
        self.grouped = true;
    }
    pub fn endGroup(self: *Recorder) void {
        if (self.timeline) |*timeline| timeline.endGroup();
        self.grouped = false;
    }
    pub fn deinit(self: *Recorder) void {
        if (self.undo) |u| self.allocator.free(u);
        if (self.timeline) |*timeline| timeline.deinit();
        self.timeline = null;
        self.undo = null;
    }
    pub fn configure(self: *Recorder, limit: usize) !void {
        if (limit > 32) return error.HistoryLimit;
        const fresh = if (limit == 0) null else try self.allocator.alloc(Machine, limit);
        if (self.undo) |old| self.allocator.free(old);
        if (self.timeline) |*timeline| timeline.deinit();
        self.timeline = null;
        self.undo = fresh;
        self.clear();
    }
    pub fn configureDelta(self: *Recorder, limit: usize) !void {
        var fresh = try Timeline.init(self.allocator, limit, Timeline.default_patches);
        errdefer fresh.deinit();
        if (self.undo) |old| self.allocator.free(old);
        if (self.timeline) |*timeline| timeline.deinit();
        self.undo = null;
        self.timeline = fresh;
        self.clear();
    }
    pub fn capacity(self: *const Recorder) usize {
        if (self.timeline) |timeline| return timeline.entries.len;
        return if (self.undo) |u| u.len else 0;
    }
    pub fn allocatedBytes(self: *const Recorder) usize {
        if (self.timeline) |timeline| return timeline.allocatedBytes();
        return if (self.undo) |u| u.len * @sizeOf(Machine) else 0;
    }
    pub fn recordWrites(self: *Recorder, m: *const Machine) void {
        if (self.timeline) |*timeline| {
            timeline.observeWrites(m.bus.writes[0..m.bus.write_count]);
            self.undo_count = timeline.count;
        }
    }
    pub fn clear(self: *Recorder) void {
        if (self.timeline) |*timeline| timeline.clear();
        self.grouped = false;
        self.undo_next = 0;
        self.undo_count = 0;
        self.trace_count = 0;
        self.trace_next = 0;
    }
    /// Record an external device transition in the same exact-state undo ring.
    pub fn capture(self: *Recorder, m: *const Machine) void {
        if (self.grouped) return;
        if (self.timeline) |*timeline| {
            timeline.capture(m);
            self.undo_count = timeline.count;
        }
        if (self.undo) |u| {
            u[self.undo_next] = m.*;
            self.undo_next = (self.undo_next + 1) % u.len;
            self.undo_count = @min(self.undo_count + 1, u.len);
        }
    }
    pub fn step(self: *Recorder, m: *Machine) void {
        self.stepAudio(m, null);
    }
    pub fn stepAudio(self: *Recorder, m: *Machine, output: ?*[800]i16) void {
        if (m.cpu.halted or m.cpu.paused or m.cpu.trap != null) return;
        self.capture(m);
        const before = m.cpu;
        const pc: usize = before.pc;
        const word: u16 = if (pc <= 65534) @as(u16, m.bus.bytes[pc]) | (@as(u16, m.bus.bytes[pc + 1]) << 8) else 0;
        const immediate: u16 = if (pc <= 65532) @as(u16, m.bus.bytes[pc + 2]) | (@as(u16, m.bus.bytes[pc + 3]) << 8) else 0;
        const entries = m.irq_entries;
        m.stepAudio(output);
        self.recordWrites(m);
        self.trace[self.trace_next] = .{ .irq_entry = if (m.irq_entries != entries) m.bus.irq.active() else null, .profile = m.bus.profile, .slots = m.slots, .before = before, .after = m.cpu, .writes = m.bus.writes, .count = m.bus.write_count, .word = word, .immediate = immediate, .length = if (@import("../arch/isa.zig").decodeProfile(word, m.bus.profile)) |i| i.len else |_| 2 };
        self.trace_next = (self.trace_next + 1) % self.trace.len;
        self.trace_count = @min(self.trace_count + 1, self.trace.len);
    }
    pub fn reverse(self: *Recorder, m: *Machine) !void {
        if (self.timeline) |*timeline| {
            try timeline.reverse(m);
            self.undo_count = timeline.count;
            self.trace_count = 0;
            self.trace_next = 0;
            return;
        }
        const u = self.undo orelse return error.HistoryDisabled;
        if (self.undo_count == 0) return error.HistoryEmpty;
        self.undo_next = (self.undo_next + u.len - 1) % u.len;
        m.* = u[self.undo_next];
        self.undo_count -= 1;
        self.trace_count = 0;
        self.trace_next = 0;
    }
    pub fn print(self: *const Recorder, w: *std.Io.Writer, requested: usize) !void {
        const count = @min(requested, self.trace_count);
        for (0..count) |k| {
            const t = &self.trace[(self.trace_next + self.trace.len - count + k) % self.trace.len];
            if (t.profile == .v2) try w.print("slot={d} ", .{t.slots});
            if (t.irq_entry) |vector| try w.print("IRQ{d} entry ", .{vector});
            try w.print("{x:0>4}: opcode={x:0>4}", .{ t.before.pc, t.word });
            if (t.length == 4) try w.print(" word1={x:0>4}", .{t.immediate});
            try w.print(" PC->{x:0>4} flags {x}->{x}", .{ t.after.pc, t.before.flags, t.after.flags });
            for (t.before.r, t.after.r, 0..) |old, new, r| if (old != new) {
                try w.print(" R{d}:{x:0>4}->{x:0>4}", .{ r, old, new });
            };
            if (t.before.sp != t.after.sp) try w.print(" SP:{x:0>4}->{x:0>4}", .{ t.before.sp, t.after.sp });
            for (t.writes[0..t.count]) |event| try w.print(" [{x:0>4}]:{x:0>2}->{x:0>2}", .{ event.address, event.old, event.new });
            if (t.after.trap) |trap| try w.print(" trap={s}", .{@errorName(trap.kind)});
            try w.writeByte('\n');
        }
    }
};

test "delta and complete-state rings agree after wrap eviction reverse branch and groups" {
    const a = std.testing.allocator;
    const asm16 = @import("../asm/assembler.zig");
    var diagnostic: asm16.Diagnostic = .{};
    const image = try asm16.assemble(a, "LDI R0, 256\nLDI R1, 0\nloop: INC R1\nSTW R1, [R0]\nLDI R2, 0xc000\nSTW R1, [R2]\nLDI R2, 0xd820\nSTB R1, [R2]\nLDI R2, 0xd801\nLDB R3, [R2]\nJMP loop", &diagnostic);
    defer image.deinit();
    var complete: Machine = .{};
    try complete.load(image.image);
    var delta = complete;
    var left: Recorder = .{ .allocator = a };
    defer left.deinit();
    var right: Recorder = .{ .allocator = a };
    defer right.deinit();
    try left.configure(32);
    try right.configureDelta(32);
    const snap = @import("../core/snapshot.zig");
    for (0..320) |action| {
        if (action % 13 == 0) {
            left.capture(&complete);
            right.capture(&delta);
            complete.injectInput(@truncate(action));
            delta.injectInput(@truncate(action));
        }
        if (action % 7 == 0) {
            left.beginGroup(&complete);
            right.beginGroup(&delta);
            for (0..37) |_| {
                left.step(&complete);
                right.step(&delta);
            }
            complete.bus.frame +%= 1;
            delta.bus.frame +%= 1;
            complete.bus.vblank = true;
            delta.bus.vblank = true;
            left.endGroup();
            right.endGroup();
        } else {
            left.step(&complete);
            right.step(&delta);
        }
        if (action % 31 == 30) {
            for (0..17) |_| {
                try left.reverse(&complete);
                try right.reverse(&delta);
            }
        }
        const expected = try snap.encodeChecked(a, &complete);
        defer a.free(expected);
        const actual = try snap.encodeChecked(a, &delta);
        defer a.free(actual);
        try std.testing.expectEqualSlices(u8, expected, actual);
        try std.testing.expectEqual(left.undo_count, right.undo_count);
    }
    while (left.undo_count > 0) {
        try left.reverse(&complete);
        try right.reverse(&delta);
        const expected = try snap.encodeChecked(a, &complete);
        defer a.free(expected);
        const actual = try snap.encodeChecked(a, &delta);
        defer a.free(actual);
        try std.testing.expectEqualSlices(u8, expected, actual);
    }
    try std.testing.expectError(error.HistoryEmpty, right.reverse(&delta));
}

test "delta allocation failure preserves an existing recorder configuration" {
    const Check = struct {
        fn run(a: std.mem.Allocator) !void {
            var recorder: Recorder = .{ .allocator = a };
            defer recorder.deinit();
            try recorder.configure(2);
            try recorder.configureDelta(16);
            try std.testing.expectEqual(16, recorder.capacity());
            try recorder.configure(0);
            try std.testing.expectEqual(0, recorder.capacity());
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}

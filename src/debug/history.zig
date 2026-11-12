const std = @import("std");
const Machine = @import("../core/machine.zig").Machine;
const Cpu = @import("../core/cpu.zig").Cpu;
const Write = @import("../core/bus.zig").Write;
pub const Trace = struct { irq_entry: ?u8 = null, profile: @import("../arch/isa.zig").Profile = .v1, slots: u64 = 0, before: Cpu, after: Cpu, writes: [6]Write, count: u3, word: u16, immediate: u16, length: u3 };
pub const Recorder = struct {
    allocator: std.mem.Allocator = std.heap.page_allocator,
    trace: [128]Trace = undefined,
    trace_next: usize = 0,
    trace_count: usize = 0,
    undo: ?[]Machine = null,
    undo_next: usize = 0,
    undo_count: usize = 0,
    pub fn deinit(self: *Recorder) void {
        if (self.undo) |u| self.allocator.free(u);
        self.undo = null;
    }
    pub fn configure(self: *Recorder, limit: usize) !void {
        if (limit > 32) return error.HistoryLimit;
        const fresh = if (limit == 0) null else try self.allocator.alloc(Machine, limit);
        if (self.undo) |old| self.allocator.free(old);
        self.undo = fresh;
        self.clear();
    }
    pub fn clear(self: *Recorder) void {
        self.undo_next = 0;
        self.undo_count = 0;
        self.trace_count = 0;
        self.trace_next = 0;
    }
    /// Record an external device transition in the same exact-state undo ring.
    pub fn capture(self: *Recorder, m: *const Machine) void {
        if (self.undo) |u| {
            u[self.undo_next] = m.*;
            self.undo_next = (self.undo_next + 1) % u.len;
            self.undo_count = @min(self.undo_count + 1, u.len);
        }
    }
    pub fn step(self: *Recorder, m: *Machine) void {
        if (m.cpu.halted or m.cpu.paused or m.cpu.trap != null) return;
        self.capture(m);
        const before = m.cpu;
        const pc: usize = before.pc;
        const word: u16 = if (pc <= 65534) @as(u16, m.bus.bytes[pc]) | (@as(u16, m.bus.bytes[pc + 1]) << 8) else 0;
        const immediate: u16 = if (pc <= 65532) @as(u16, m.bus.bytes[pc + 2]) | (@as(u16, m.bus.bytes[pc + 3]) << 8) else 0;
        const entries = m.irq_entries;
        m.step();
        self.trace[self.trace_next] = .{ .irq_entry = if (m.irq_entries != entries) m.bus.irq.active() else null, .profile = m.bus.profile, .slots = m.slots, .before = before, .after = m.cpu, .writes = m.bus.writes, .count = m.bus.write_count, .word = word, .immediate = immediate, .length = if (@import("../arch/isa.zig").decodeProfile(word, m.bus.profile)) |i| i.len else |_| 2 };
        self.trace_next = (self.trace_next + 1) % self.trace.len;
        self.trace_count = @min(self.trace_count + 1, self.trace.len);
    }
    pub fn reverse(self: *Recorder, m: *Machine) !void {
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

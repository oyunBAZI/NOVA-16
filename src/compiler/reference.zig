//! Independent bounded AST execution oracle. Never reads generated assembly/ROM,
//! invokes CPU instructions, or calls the compiler's arithmetic evaluator.
const std = @import("std");
const c = @import("compiler.zig");
const s = c.syntax;
const Cell = struct { global: bool, index: usize };
pub const Interpreter = struct {
    context: *const c.Context,
    globals: [8192]u16 = @splat(0),
    frames: [64][128]u16 = @splat(@splat(0)),
    constants: [1024]u16 = @splat(0),
    slots: [1024]usize = @splat(0),
    depth: usize = 0,
    remaining: usize = 1000000,
    fn charge(self: *Interpreter) !void {
        if (self.remaining == 0) return error.ReferenceWorkLimit;
        self.remaining -= 1;
    }
    fn words(self: *const Interpreter, ty: usize) usize {
        const t = self.context.tree.types[ty];
        return switch (t.kind) {
            .array => t.length,
            .record => t.fields.len,
            else => 1,
        };
    }
    pub fn run(self: *Interpreter) !u16 {
        var global: usize = 0;
        var local: [128]usize = @splat(0);
        for (self.context.variables.items, 0..) |v, i| {
            if (v.function == s.none) {
                self.slots[i] = global;
                global += self.words(v.ty);
            } else {
                self.slots[i] = local[v.function];
                local[v.function] += self.words(v.ty);
            }
        }
        for (self.context.tree.roots) |root| {
            const n = self.context.tree.nodes[root];
            if (n.tag == .decl and n.a != s.none) {
                const value = try self.evaluate(n.a);
                if (n.value == 1) self.constants[n.binding] = value else self.globals[self.slots[n.binding]] = value;
            }
        }
        const main = self.context.names.get("main") orelse return error.MissingMain;
        return self.call(main, &.{});
    }
    fn cell(self: *Interpreter, id: usize) anyerror!Cell {
        const n = self.context.tree.nodes[id];
        switch (n.tag) {
            .name => {
                const v = self.context.variables.items[n.binding];
                return .{ .global = v.function == s.none, .index = self.slots[n.binding] };
            },
            .member => {
                var base = try self.cell(n.a);
                const ty = self.context.tree.types[self.context.tree.nodes[n.a].ty];
                for (ty.fields, 0..) |field, index| if (eq(field.name.text, n.token.text)) {
                    base.index += index;
                    return base;
                };
                return error.UnknownField;
            },
            .index => {
                var base = try self.cell(n.a);
                const index = try self.evaluate(n.b);
                const ty = self.context.tree.types[self.context.tree.nodes[n.a].ty];
                if (index >= ty.length) return error.ReferenceBounds;
                base.index += index;
                return base;
            },
            else => return error.ExpectedLvalue,
        }
    }
    fn read(self: *Interpreter, address: Cell) u16 {
        return if (address.global) self.globals[address.index] else self.frames[self.depth - 1][address.index];
    }
    fn write(self: *Interpreter, address: Cell, value: u16) void {
        if (address.global) self.globals[address.index] = value else self.frames[self.depth - 1][address.index] = value;
    }
    fn call(self: *Interpreter, function: usize, args: []const u16) anyerror!u16 {
        try self.charge();
        if (self.depth == 64) return error.ReferenceFrameLimit;
        const f = self.context.tree.nodes[self.context.functions.items[function].node];
        self.frames[self.depth] = @splat(0);
        self.depth += 1;
        defer self.depth -= 1;
        for (f.items, args) |parameter, arg| {
            const n = self.context.tree.nodes[parameter];
            self.frames[self.depth - 1][self.slots[n.binding]] = arg;
        }
        return (try self.statement(f.a)) orelse error.ReferenceMissingReturn;
    }
    fn statement(self: *Interpreter, id: usize) anyerror!?u16 {
        try self.charge();
        const n = self.context.tree.nodes[id];
        switch (n.tag) {
            .block => {
                for (n.items) |child| if (try self.statement(child)) |result| return result;
            },
            .ret => return try self.evaluate(n.a),
            .expression => {
                _ = try self.evaluate(n.a);
            },
            .decl => {
                const cell_: Cell = .{ .global = false, .index = self.slots[n.binding] };
                if (n.a != s.none) self.write(cell_, try self.evaluate(n.a)) else for (0..self.words(n.ty)) |i| self.write(.{ .global = false, .index = cell_.index + i }, 0);
            },
            .assign => {
                const address = try self.cell(n.a);
                self.write(address, try self.evaluate(n.b));
            },
            .conditional => {
                if (try self.evaluate(n.a) != 0) return self.statement(n.b) else if (n.c != s.none) return self.statement(n.c);
            },
            .loop => {
                while (try self.evaluate(n.a) != 0) if (try self.statement(n.b)) |result| return result;
            },
            else => return error.UnsupportedReferenceOperation,
        }
        return null;
    }
    fn evaluate(self: *Interpreter, id: usize) anyerror!u16 {
        try self.charge();
        const n = self.context.tree.nodes[id];
        return switch (n.tag) {
            .number, .boolean => n.value,
            .name => blk: {
                const v = self.context.variables.items[n.binding];
                if (v.function == s.none and v.constant) break :blk self.constants[n.binding];
                break :blk self.read(try self.cell(id));
            },
            .index, .member => self.read(try self.cell(id)),
            .unary => blk: {
                const v = try self.evaluate(n.a);
                break :blk if (eq(n.token.text, "-")) wrap(-@as(i64, v)) else if (eq(n.token.text, "~")) 65535 - v else @intFromBool(v == 0);
            },
            .select => if (try self.evaluate(n.a) != 0) self.evaluate(n.b) else self.evaluate(n.c),
            .binary => blk: {
                const left = try self.evaluate(n.a);
                const op = n.token.text;
                if (eq(op, "&&") and left == 0) break :blk 0;
                if (eq(op, "||") and left != 0) break :blk 1;
                const right = try self.evaluate(n.b);
                break :blk try arithmetic(op, left, right, self.context.tree.nodes[n.a].ty == 1);
            },
            .call => blk: {
                const name = self.context.tree.nodes[n.a].token.text;
                if (eq(name, "u16") or eq(name, "i16")) break :blk try self.evaluate(n.items[0]);
                if (eq(name, "bool")) break :blk @intFromBool(try self.evaluate(n.items[0]) != 0);
                if (n.binding == s.none) return error.UnsupportedReferenceOperation;
                var args: [4]u16 = undefined;
                for (n.items, 0..) |arg, index| args[index] = try self.evaluate(arg);
                break :blk try self.call(n.binding, args[0..n.items.len]);
            },
            else => error.UnsupportedReferenceOperation,
        };
    }
};
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn wrap(value: i64) u16 {
    return @intCast(@mod(value, 65536));
}
fn arithmetic(op: []const u8, x: u16, y: u16, signed: bool) !u16 {
    const a: i64 = if (signed) @as(i16, @bitCast(x)) else x;
    const b: i64 = if (signed) @as(i16, @bitCast(y)) else y;
    if (eq(op, "+")) return wrap(a + b);
    if (eq(op, "-")) return wrap(a - b);
    if (eq(op, "*")) return wrap(a * b);
    if (eq(op, "&")) return x & y;
    if (eq(op, "|")) return x | y;
    if (eq(op, "^")) return x ^ y;
    const power = @as(i64, 1) << @as(u6, @intCast(@as(u32, y) % 16));
    if (eq(op, "<<")) return wrap(@as(i64, x) * power);
    if (eq(op, ">>")) return wrap(@divFloor(a, power));
    if (eq(op, "==")) return @intFromBool(x == y);
    if (eq(op, "!=")) return @intFromBool(x != y);
    if (eq(op, "<")) return @intFromBool(a < b);
    if (eq(op, ">")) return @intFromBool(a > b);
    if (eq(op, "<=")) return @intFromBool(a <= b);
    if (eq(op, ">=")) return @intFromBool(a >= b);
    if (eq(op, "&&")) return @intFromBool(x != 0 and y != 0);
    if (eq(op, "||")) return @intFromBool(x != 0 or y != 0);
    if (b == 0) return error.ReferenceDivisionByZero;
    if (eq(op, "/")) return wrap(@divTrunc(a, b));
    if (eq(op, "%")) return wrap(@rem(a, b));
    return error.UnsupportedReferenceOperation;
}

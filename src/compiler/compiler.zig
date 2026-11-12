//! Bounded typed front end and direct ISA V1 assembly lowering. No host execution.
const std = @import("std");
pub const syntax = @import("syntax.zig");
const s = syntax;
const Id = s.Id;
const none = s.none;
const asm16 = @import("../asm/assembler.zig");
pub const Diagnostic = asm16.Diagnostic;
pub const Origin = struct { line: usize, column: usize };
pub const Variable = struct { name: []const u8, ty: Id, address: u16, function: Id, constant: bool, constant_value: ?u16 = null, visible: bool = true, end_block: usize = none };
pub const Function = struct { node: Id, words: u16 = 0, reachable: bool = false };
pub const Result = struct {
    context: *Context,
    assembly: []const u8,
    program: asm16.Result,
    pub fn deinit(self: Result) void {
        const owner = self.context.owner;
        owner.free(self.context.buffer);
        owner.destroy(self.context);
    }
};
pub const Context = struct {
    owner: std.mem.Allocator,
    buffer: []u8,
    fixed: std.heap.FixedBufferAllocator,
    a: std.mem.Allocator = undefined,
    source: []const u8,
    diag: *Diagnostic,
    tree: s.Syntax = undefined,
    variables: std.ArrayList(Variable) = .empty,
    functions: std.ArrayList(Function) = .empty,
    names: std.StringHashMap(Id) = undefined,
    out: std.Io.Writer.Allocating = undefined,
    origins: std.ArrayList(Origin) = .empty,
    current_function: Id = none,
    static_end: u16 = 0x100,
    label: usize = 0,
    emitting: bool = true,
    line: usize = 0,
    column: usize = 1,
    library_plan: ?@import("guest_linker.zig").Plan = null,
    fn focus(self: *Context, t: s.Token) void {
        self.diag.* = .{ .token = t.text, .offset = @intFromPtr(t.text.ptr) - @intFromPtr(self.source.ptr), .length = t.text.len, .line = t.line, .column = t.column };
    }
    fn emit(self: *Context, comptime fmt: []const u8, args: anytype) !void {
        if (!self.emitting) return;
        const begin = self.out.written().len;
        try self.out.writer.print(fmt, args);
        try self.out.writer.writeByte('\n');
        if (self.out.written().len > 1024 * 1024) return error.GeneratedSourceLimit;
        for (0..std.mem.count(u8, self.out.written()[begin..], "\n")) |_| try self.origins.append(self.a, .{ .line = self.line, .column = self.column });
    }
    fn nextLabel(self: *Context) usize {
        self.label += 1;
        return self.label;
    }
    fn find(self: *Context, name: []const u8) !Id {
        var i = self.variables.items.len;
        while (i > 0) {
            i -= 1;
            const v = self.variables.items[i];
            if (v.visible and (v.function == none or v.function == self.current_function) and eq(v.name, name)) return i;
        }
        return error.UndefinedVariable;
    }
    fn declare(self: *Context, node: Id) !Id {
        const n = &self.tree.nodes[node];
        self.focus(n.token);
        if (reserved(n.token.text) or std.mem.startsWith(u8, n.token.text, "n16_") or std.mem.startsWith(u8, n.token.text, "_c_") or builtin(n.token.text) != null) return error.ReservedName;
        if (self.find(n.token.text)) |_| return error.DuplicateVariable else |_| {}
        if (self.names.contains(n.token.text)) return error.DuplicateSymbol;
        if (self.variables.items.len == 1024) return error.VariableLimit;
        const words = self.tree.types[n.ty].words;
        var location: u16 = undefined;
        if (self.current_function == none) {
            location = self.static_end;
            if (@as(u32, location) + @as(u32, words) * 2 > 0x4000) return error.StaticMemoryLimit;
            self.static_end += words * 2;
        } else {
            const f = &self.functions.items[self.current_function];
            location = f.words * 2;
            if (@as(u32, f.words) + words > 128) return error.LocalFrameLimit;
            f.words += words;
        }
        n.binding = self.variables.items.len;
        try self.variables.append(self.a, .{ .name = n.token.text, .ty = n.ty, .address = location, .function = self.current_function, .constant = n.value == 1 });
        return n.binding;
    }
    fn coerce(self: *Context, expected: Id, expr: Id) anyerror!void {
        const actual = try self.infer(expr);
        if (expected == actual) return;
        const n = &self.tree.nodes[expr];
        self.focus(n.token);
        if (n.tag == .number and expected < 2) {
            if (expected == 1 and n.value > 32767) return error.IntegerRange;
            n.ty = expected;
            return;
        }
        return error.TypeMismatch;
    }
    pub fn infer(self: *Context, id: Id) anyerror!Id {
        const n = &self.tree.nodes[id];
        self.focus(n.token);
        if (n.ty != none) return n.ty;
        n.ty = switch (n.tag) {
            .number => 0,
            .boolean => 2,
            .name => blk: {
                n.binding = try self.find(n.token.text);
                break :blk self.variables.items[n.binding].ty;
            },
            .unary => blk: {
                const ty = try self.infer(n.a);
                if (eq(n.token.text, "!")) {
                    if (ty != 2) return error.ExpectedBool;
                    break :blk 2;
                }
                if (ty > 1) return error.ExpectedInteger;
                if (eq(n.token.text, "-") and self.tree.nodes[n.a].tag == .number) {
                    if (self.tree.nodes[n.a].value > 32768) return error.IntegerRange;
                    break :blk 1;
                }
                break :blk ty;
            },
            .binary => blk: {
                var left = try self.infer(n.a);
                const right = try self.infer(n.b);
                if (eq(n.token.text, "<<") or eq(n.token.text, ">>")) {
                    if (left > 1 or right > 1) return error.ExpectedInteger;
                    break :blk left;
                }
                if (left != right and self.tree.nodes[n.a].tag == .number) {
                    try self.coerce(right, n.a);
                    left = right;
                } else try self.coerce(left, n.b);
                if (eq(n.token.text, "&&") or eq(n.token.text, "||")) {
                    if (left != 2) return error.ExpectedBool;
                    break :blk 2;
                }
                if (eq(n.token.text, "==") or eq(n.token.text, "!=")) {
                    if (left > 2) return error.AggregateValue;
                    break :blk 2;
                }
                if (left > 1) return error.ExpectedInteger;
                if (isCompare(n.token.text)) break :blk 2;
                if (eq(n.token.text, "/") or eq(n.token.text, "%")) {
                    if (self.constant(n.b)) |value| {
                        if (value == 0) return error.DivisionByZero;
                    } else |_| {}
                }
                break :blk left;
            },
            .select => blk: {
                if (try self.infer(n.a) != 2) return error.ExpectedBool;
                const ty = try self.infer(n.b);
                try self.coerce(ty, n.c);
                break :blk ty;
            },
            .call => blk: {
                if (self.tree.nodes[n.a].tag != .name) return error.ExpectedFunction;
                const name = self.tree.nodes[n.a].token.text;
                if (eq(name, "u16") or eq(name, "i16") or eq(name, "bool")) {
                    if (n.items.len != 1) return error.ArgumentCount;
                    if (try self.infer(n.items[0]) > 2) return error.AggregateValue;
                    break :blk if (eq(name, "u16")) 0 else if (eq(name, "i16")) 1 else 2;
                }
                if (builtin(name)) |b| {
                    if (n.items.len != b.arity) return error.ArgumentCount;
                    for (n.items) |arg| try self.coerce(0, arg);
                    break :blk 0;
                }
                const f = self.names.get(name) orelse return error.UndefinedFunction;
                n.binding = f;
                const target = self.tree.nodes[self.functions.items[f].node];
                if (n.items.len != target.items.len) return error.ArgumentCount;
                for (n.items, target.items) |arg, parameter| try self.coerce(self.tree.nodes[parameter].ty, arg);
                break :blk target.ty;
            },
            .index => blk: {
                const ty = try self.infer(n.a);
                const array = self.tree.types[ty];
                if (array.kind != .array) return error.ExpectedArray;
                try self.coerce(0, n.b);
                if (self.constant(n.b)) |index| {
                    if (index >= array.length) return error.StaticBounds;
                } else |_| {}
                break :blk array.element;
            },
            .member => blk: {
                const ty = self.tree.types[try self.infer(n.a)];
                if (ty.kind != .record) return error.ExpectedStruct;
                for (ty.fields) |field| if (eq(field.name.text, n.token.text)) {
                    n.value = field.offset;
                    break :blk field.ty;
                };
                return error.UnknownField;
            },
            else => return error.ExpectedExpression,
        };
        return n.ty;
    }
    pub fn constant(self: *Context, id: Id) anyerror!u16 {
        const n = self.tree.nodes[id];
        return switch (n.tag) {
            .number, .boolean => n.value,
            .name => self.variables.items[try self.find(n.token.text)].constant_value orelse error.NonConstantInitializer,
            .unary => blk: {
                const value = try self.constant(n.a);
                break :blk if (eq(n.token.text, "-")) 0 -% value else if (eq(n.token.text, "~")) ~value else @intFromBool(value == 0);
            },
            .binary => binaryValue(n.token.text, try self.constant(n.a), try self.constant(n.b), try self.infer(n.a)),
            .select => if (try self.constant(n.a) != 0) self.constant(n.b) else self.constant(n.c),
            .call => blk: {
                if (n.items.len != 1) return error.NonConstantInitializer;
                const name = self.tree.nodes[n.a].token.text;
                const value = try self.constant(n.items[0]);
                if (eq(name, "bool")) break :blk @intFromBool(value != 0);
                if (eq(name, "u16") or eq(name, "i16")) break :blk value;
                return error.NonConstantInitializer;
            },
            else => error.NonConstantInitializer,
        };
    }
    fn mutable(self: *Context, id: Id) anyerror!void {
        const n = self.tree.nodes[id];
        switch (n.tag) {
            .name => {
                _ = try self.infer(id);
                if (self.variables.items[self.tree.nodes[id].binding].constant) return error.ImmutableVariable;
            },
            .index, .member => try self.mutable(n.a),
            else => return error.ExpectedLvalue,
        }
    }
    fn address(self: *Context, id: Id) anyerror!void {
        const n = self.tree.nodes[id];
        _ = try self.infer(id);
        switch (n.tag) {
            .name => {
                const v = self.variables.items[self.tree.nodes[id].binding];
                if (v.function == none) try self.emit("LDI R0, {d}", .{v.address}) else try self.emit("MOV R0, R7\nADDI R0, {d}", .{v.address});
            },
            .index => {
                const array = self.tree.types[try self.infer(n.a)];
                try self.address(n.a);
                try self.emit("PUSH R0", .{});
                try self.expression(n.b);
                const valid = self.nextLabel();
                try self.emit("CMPI R0, {d}\nB.CC _c_L{d}\nLDI R3, {d}\nLDI R4, 242\nSTW R3, [R4]\nJMP _c_bounds\n_c_L{d}:", .{ array.length, valid, n.token.line, valid });
                try self.emit("LDI R1, 2\nMUL R0, R1\nPOP R1\nADD R0, R1", .{});
            },
            .member => {
                try self.address(n.a);
                try self.emit("ADDI R0, {d}", .{self.tree.nodes[id].value});
            },
            else => return error.ExpectedLvalue,
        }
    }
    fn branchFalse(self: *Context, label: usize) !void {
        const skip = self.nextLabel();
        try self.emit("CMPI R0, 0\nB.NE _c_L{d}\nJMP _c_L{d}\n_c_L{d}:", .{ skip, label, skip });
    }
    pub fn expression(self: *Context, id: Id) anyerror!void {
        const n = self.tree.nodes[id];
        const ty = try self.infer(id);
        const previous = self.line;
        const previous_column = self.column;
        self.line = n.token.line;
        self.column = n.token.column;
        defer {
            self.line = previous;
            self.column = previous_column;
        }
        switch (n.tag) {
            .number, .boolean => try self.emit("LDI R0, {d}", .{n.value}),
            .name => {
                const v = self.variables.items[self.tree.nodes[id].binding];
                if (v.constant_value) |value| try self.emit("LDI R0, {d}", .{value}) else {
                    if (ty > 2) return error.AggregateValue;
                    try self.address(id);
                    try self.emit("LDW R0, [R0]", .{});
                }
            },
            .index, .member => {
                try self.address(id);
                try self.emit("LDW R0, [R0]", .{});
            },
            .unary => {
                try self.expression(n.a);
                if (eq(n.token.text, "-")) try self.emit("LDI R1, 0\nSUB R1, R0\nMOV R0, R1", .{}) else if (eq(n.token.text, "~")) try self.emit("NOT R0", .{}) else try self.booleanResult("EQ");
            },
            .binary => {
                if (eq(n.token.text, "&&") or eq(n.token.text, "||")) {
                    const done = self.nextLabel();
                    const rhs = self.nextLabel();
                    try self.expression(n.a);
                    if (eq(n.token.text, "&&")) try self.branchFalse(done) else {
                        try self.branchFalse(rhs);
                        try self.emit("JMP _c_L{d}\n_c_L{d}:", .{ done, rhs });
                    }
                    try self.expression(n.b);
                    try self.emit("_c_L{d}:", .{done});
                    return;
                }
                try self.expression(n.a);
                try self.emit("PUSH R0", .{});
                try self.expression(n.b);
                try self.emit("MOV R1, R0\nPOP R0", .{});
                const op = n.token.text;
                if (isCompare(op)) {
                    try self.emit("CMP R0, R1", .{});
                    const signed = try self.infer(n.a) == 1;
                    const cond: []const u8 = if (eq(op, "==")) "EQ" else if (eq(op, "!=")) "NE" else if (eq(op, "<")) (if (signed) "LT" else "CC") else if (eq(op, ">")) (if (signed) "GT" else "HI") else if (eq(op, "<=")) (if (signed) "LE" else "LS") else (if (signed) "GE" else "CS");
                    try self.flagResult(cond);
                } else if (eq(op, "/") or eq(op, "%")) {
                    try self.emit("CALL {s}", .{if (try self.infer(n.a) == 1) "n16_sdiv" else "n16_udiv"});
                    const valid = self.nextLabel();
                    try self.emit("CMPI R2, 1\nB.NE _c_L{d}\nLDI R3, {d}\nLDI R4, 242\nSTW R3, [R4]\nJMP _c_divzero\n_c_L{d}:", .{ valid, n.token.line, valid });
                    if (eq(op, "%")) try self.emit("MOV R0, R1", .{});
                } else {
                    const instruction: []const u8 = if (eq(op, "+")) "ADD" else if (eq(op, "-")) "SUB" else if (eq(op, "*")) "MUL" else if (eq(op, "&")) "AND" else if (eq(op, "|")) "OR" else if (eq(op, "^")) "XOR" else if (eq(op, "<<")) "SHL" else if (eq(op, ">>")) (if (ty == 1) "SAR" else "SHR") else return error.UnknownOperator;
                    try self.emit("{s} R0, R1", .{instruction});
                }
            },
            .select => {
                const no = self.nextLabel();
                const done = self.nextLabel();
                try self.expression(n.a);
                try self.branchFalse(no);
                try self.expression(n.b);
                try self.emit("JMP _c_L{d}\n_c_L{d}:", .{ done, no });
                try self.expression(n.c);
                try self.emit("_c_L{d}:", .{done});
            },
            .call => {
                const name = self.tree.nodes[n.a].token.text;
                if (eq(name, "u16") or eq(name, "i16") or eq(name, "bool")) {
                    try self.expression(n.items[0]);
                    if (ty == 2) try self.booleanResult("NE");
                    return;
                }
                for (n.items) |arg| {
                    try self.expression(arg);
                    try self.emit("PUSH R0", .{});
                }
                var i = n.items.len;
                while (i > 0) {
                    i -= 1;
                    try self.emit("POP R{d}", .{i});
                }
                if (builtin(name)) |b| {
                    if (eq(name, "peek8") or eq(name, "peek16")) try self.emit("{s} R0, [R0]", .{if (eq(name, "peek8")) "LDB" else "LDW"}) else if (eq(name, "poke8") or eq(name, "poke16")) try self.emit("{s} R1, [R0]\nLDI R0, 0", .{if (eq(name, "poke8")) "STB" else "STW"}) else {
                        try self.emit("CALL {s}", .{b.label});
                        if (b.status) try self.emit("MOV R0, R3", .{});
                    }
                } else try self.emit("CALL _c_f_{s}", .{name});
            },
            else => return error.ExpectedExpression,
        }
    }
    fn booleanResult(self: *Context, cond: []const u8) !void {
        try self.emit("CMPI R0, 0", .{});
        try self.flagResult(cond);
    }
    fn flagResult(self: *Context, cond: []const u8) !void {
        const yes = self.nextLabel();
        const end = self.nextLabel();
        try self.emit("B.{s} _c_L{d}\nLDI R0, 0\nJMP _c_L{d}\n_c_L{d}:\nLDI R0, 1\n_c_L{d}:", .{ cond, yes, end, yes, end });
    }
    fn storeVariable(self: *Context, variable: Id) !void {
        const v = self.variables.items[variable];
        if (v.function == none) try self.emit("LDI R4, {d}\nSTW R0, [R4]", .{v.address}) else try self.emit("MOV R4, R7\nADDI R4, {d}\nSTW R0, [R4]", .{v.address});
    }
    fn statement(self: *Context, id: Id) anyerror!void {
        const n = self.tree.nodes[id];
        self.focus(n.token);
        const previous = self.line;
        const previous_column = self.column;
        self.line = n.token.line;
        self.column = n.token.column;
        defer {
            self.line = previous;
            self.column = previous_column;
        }
        switch (n.tag) {
            .block => {
                const start = self.variables.items.len;
                for (n.items) |child| try self.statement(child);
                try self.emit("_c_b_{d}:", .{id});
                for (self.variables.items[start..]) |*v| {
                    v.visible = false;
                    if (v.end_block == none) v.end_block = id;
                }
            },
            .decl => {
                const index = try self.declare(id);
                if (n.a != none) {
                    if (n.ty > 2) return error.AggregateInitializer;
                    try self.coerce(n.ty, n.a);
                    try self.expression(n.a);
                    try self.storeVariable(index);
                } else {
                    const v = self.variables.items[index];
                    if (v.function == none) try self.emit("LDI R0, {d}", .{v.address}) else try self.emit("MOV R0, R7\nADDI R0, {d}", .{v.address});
                    try self.emit("LDI R1, {d}\nCALL n16_memzero", .{self.tree.types[n.ty].words * 2});
                }
                try self.emit("_c_v_{d}:", .{self.tree.nodes[id].binding});
            },
            .assign => {
                try self.mutable(n.a);
                const ty = try self.infer(n.a);
                if (ty > 2) return error.AggregateAssignment;
                try self.coerce(ty, n.b);
                try self.address(n.a);
                try self.emit("PUSH R0", .{});
                try self.expression(n.b);
                try self.emit("POP R1\nSTW R0, [R1]", .{});
            },
            .expression => try self.expression(n.a),
            .ret => {
                const f = self.tree.nodes[self.functions.items[self.current_function].node];
                try self.coerce(f.ty, n.a);
                try self.expression(n.a);
                try self.emit("JMP _c_e_{s}", .{f.token.text});
            },
            .conditional => {
                if (try self.infer(n.a) != 2) return error.ExpectedBool;
                const no = self.nextLabel();
                const end = self.nextLabel();
                try self.expression(n.a);
                try self.branchFalse(no);
                try self.statement(n.b);
                try self.emit("JMP _c_L{d}\n_c_L{d}:", .{ end, no });
                if (n.c != none) try self.statement(n.c);
                try self.emit("_c_L{d}:", .{end});
            },
            .loop => {
                if (try self.infer(n.a) != 2) return error.ExpectedBool;
                const begin = self.nextLabel();
                const end = self.nextLabel();
                try self.emit("_c_L{d}:", .{begin});
                try self.expression(n.a);
                try self.branchFalse(end);
                try self.statement(n.b);
                try self.emit("JMP _c_L{d}\n_c_L{d}:", .{ begin, end });
            },
            else => return error.ExpectedStatement,
        }
    }
    fn definitelyReturns(self: *Context, id: Id) bool {
        const n = self.tree.nodes[id];
        return switch (n.tag) {
            .ret => true,
            .block => n.items.len > 0 and self.definitelyReturns(n.items[n.items.len - 1]),
            .conditional => n.c != none and self.definitelyReturns(n.b) and self.definitelyReturns(n.c),
            else => false,
        };
    }
    fn markCalls(self: *Context, id: Id) bool {
        if (id == none) return false;
        const node = self.tree.nodes[id];
        var changed = false;
        if (node.tag == .call and self.tree.nodes[node.a].tag == .name) {
            if (self.names.get(self.tree.nodes[node.a].token.text)) |target| {
                if (!self.functions.items[target].reachable) {
                    self.functions.items[target].reachable = true;
                    changed = true;
                }
            }
        }
        for ([_]Id{ node.a, node.b, node.c }) |child| changed = self.markCalls(child) or changed;
        for (node.items) |child| changed = self.markCalls(child) or changed;
        return changed;
    }
    fn lower(self: *Context) !void {
        self.names = .init(self.a);
        self.out = .init(self.a);
        for (self.tree.roots) |root| {
            const n = self.tree.nodes[root];
            if (n.tag == .function) {
                self.focus(n.token);
                if (self.functions.items.len == 128) return error.FunctionLimit;
                if (reserved(n.token.text) or self.names.contains(n.token.text) or builtin(n.token.text) != null or std.mem.startsWith(u8, n.token.text, "_c_") or std.mem.startsWith(u8, n.token.text, "n16_")) return error.DuplicateFunction;
                try self.names.put(n.token.text, self.functions.items.len);
                try self.functions.append(self.a, .{ .node = root });
            }
        }
        const main = self.names.get("main") orelse return error.MissingMain;
        if (self.tree.nodes[self.functions.items[main].node].items.len != 0) return error.MainArguments;
        self.functions.items[main].reachable = true;
        var changed = true;
        while (changed) {
            changed = false;
            for (self.functions.items) |function| if (function.reachable) {
                changed = self.markCalls(self.tree.nodes[function.node].a) or changed;
            };
        }
        try self.emit(".entry _c_boot\n_c_boot:\nLDI R7, 0x8000", .{});
        for (self.tree.roots) |root| {
            const n = self.tree.nodes[root];
            if (n.tag == .decl) {
                const index = try self.declare(root);
                if (n.a != none) {
                    try self.coerce(n.ty, n.a);
                    const value = try self.constant(n.a);
                    if (n.value == 1) self.variables.items[index].constant_value = value else {
                        try self.emit("LDI R0, {d}", .{value});
                        try self.storeVariable(index);
                    }
                }
            }
        }
        try self.emit("CALL _c_f_main\nHALT", .{});
        for (self.functions.items, 0..) |function, index| {
            // Still lower/type-check unused functions, preserving diagnostics and
            // resource limits; only suppress their code and source locations.
            self.emitting = function.reachable;
            self.current_function = index;
            const f = self.tree.nodes[function.node];
            self.line = f.token.line;
            self.column = f.token.column;
            self.focus(f.token);
            if (!self.definitelyReturns(f.a)) return error.MissingReturn;
            try self.emit("_c_f_{s}:\nPUSH R4\nPUSH R5\nPUSH R6\nPUSH R7", .{f.token.text});
            const valid = self.nextLabel();
            try self.emit("CMPI R7, 0x4100\nB.CS _c_L{d}\nLDI R3, {d}\nLDI R4, 242\nSTW R3, [R4]\nJMP _c_stack\n_c_L{d}:\nLDI R4, 256\nSUB R7, R4", .{ valid, f.token.line, valid });
            const start = self.variables.items.len;
            for (f.items, 0..) |param, arg| {
                const v = try self.declare(param);
                try self.emit("MOV R4, R7\nADDI R4, {d}\nSTW R{d}, [R4]", .{ self.variables.items[v].address, arg });
                try self.emit("_c_v_{d}:", .{v});
            }
            try self.statement(f.a);
            try self.emit("_c_e_{s}:\nPOP R7\nPOP R6\nPOP R5\nPOP R4\nRET\n_c_end_{s}:", .{ f.token.text, f.token.text });
            for (self.variables.items[start..]) |*v| v.visible = false;
        }
        self.emitting = true;
        self.current_function = none;
        self.line = 0;
        try self.emit("_c_bounds: LDI R0, 1\nJMP _c_fail\n_c_divzero: LDI R0, 2\nJMP _c_fail\n_c_stack: LDI R0, 3\n_c_fail: LDI R1, 0x00f0\nSTW R0, [R1]\nBRK\nHALT", .{});
        // Resolve exact assembly references against the shared ABI1 library.
        // Source origins are appended only for blocks that are actually linked.
        const library = @import("guest").all;
        self.library_plan = try @import("guest_linker.zig").plan(self.a, self.out.written(), library);
        for (self.library_plan.?.blocks) |block| {
            if (!block.retained) continue;
            var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, library[block.start..block.end], "\n"), '\n');
            while (lines.next()) |line| try self.emit("{s}", .{line});
        }
    }
};
fn reserved(name: []const u8) bool {
    for ([_][]const u8{ "fn", "var", "const", "struct", "if", "else", "while", "return", "true", "false", "u16", "i16", "bool" }) |word| if (eq(word, name)) return true;
    return false;
}
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn isCompare(op: []const u8) bool {
    for ([_][]const u8{ "==", "!=", "<", ">", "<=", ">=" }) |text| if (eq(op, text)) return true;
    return false;
}
pub const Builtin = struct { arity: usize, label: []const u8, status: bool = false };
pub fn builtin(name: []const u8) ?Builtin {
    const names = [_]struct { name: []const u8, b: Builtin }{
        .{ .name = "peek8", .b = .{ .arity = 1, .label = "" } },                            .{ .name = "peek16", .b = .{ .arity = 1, .label = "" } },                           .{ .name = "poke8", .b = .{ .arity = 2, .label = "" } },                           .{ .name = "poke16", .b = .{ .arity = 2, .label = "" } },
        .{ .name = "color", .b = .{ .arity = 1, .label = "n16_color" } },                   .{ .name = "clear", .b = .{ .arity = 1, .label = "n16_clear" } },                   .{ .name = "pixel", .b = .{ .arity = 3, .label = "n16_pixel", .status = true } },  .{ .name = "rect", .b = .{ .arity = 4, .label = "n16_rect", .status = true } },
        .{ .name = "glyph", .b = .{ .arity = 3, .label = "n16_glyph", .status = true } },   .{ .name = "number", .b = .{ .arity = 3, .label = "n16_number", .status = true } }, .{ .name = "buttons", .b = .{ .arity = 0, .label = "n16_buttons" } },              .{ .name = "frame", .b = .{ .arity = 0, .label = "n16_frame" } },
        .{ .name = "wait_frame", .b = .{ .arity = 1, .label = "n16_wait_frame" } },         .{ .name = "random", .b = .{ .arity = 1, .label = "n16_random" } },                 .{ .name = "copy", .b = .{ .arity = 3, .label = "n16_memcopy", .status = true } }, .{ .name = "zero", .b = .{ .arity = 2, .label = "n16_memzero", .status = true } },
        .{ .name = "bitmap", .b = .{ .arity = 4, .label = "n16_bitmap", .status = true } },
    };
    for (names) |entry| if (eq(entry.name, name)) return entry.b;
    return null;
}
pub fn binaryValue(op: []const u8, x: u16, y: u16, ty: Id) !u16 {
    if (eq(op, "+")) return x +% y;
    if (eq(op, "-")) return x -% y;
    if (eq(op, "*")) return x *% y;
    if (eq(op, "&")) return x & y;
    if (eq(op, "|")) return x | y;
    if (eq(op, "^")) return x ^ y;
    if (eq(op, "<<")) return x << @as(u4, @truncate(y));
    if (eq(op, ">>")) return if (ty == 1) @bitCast(@as(i16, @bitCast(x)) >> @as(u4, @truncate(y))) else x >> @as(u4, @truncate(y));
    if (eq(op, "==")) return @intFromBool(x == y);
    if (eq(op, "!=")) return @intFromBool(x != y);
    if (eq(op, "&&")) return @intFromBool(x != 0 and y != 0);
    if (eq(op, "||")) return @intFromBool(x != 0 or y != 0);
    const a: i32 = if (ty == 1) @as(i16, @bitCast(x)) else x;
    const b: i32 = if (ty == 1) @as(i16, @bitCast(y)) else y;
    if (eq(op, "<")) return @intFromBool(a < b);
    if (eq(op, ">")) return @intFromBool(a > b);
    if (eq(op, "<=")) return @intFromBool(a <= b);
    if (eq(op, ">=")) return @intFromBool(a >= b);
    if (y == 0) return error.DivisionByZero;
    const value = if (eq(op, "/")) @divTrunc(a, b) else @rem(a, b);
    return @truncate(@as(u32, @bitCast(value)));
}
pub fn compile(owner: std.mem.Allocator, source: []const u8, diag: *Diagnostic) !Result {
    diag.* = .{};
    return compileInner(owner, source, diag) catch |err| {
        const offset = @min(diag.offset, source.len);
        diag.token = source[offset..][0..@min(diag.length, source.len - offset)];
        diag.code = @errorName(err);
        diag.reason = @errorName(err);
        return err;
    };
}
fn compileInner(owner: std.mem.Allocator, source: []const u8, diag: *Diagnostic) !Result {
    if (source.len > 1024 * 1024) return error.SourceTooLarge;
    const ctx = try owner.create(Context);
    errdefer owner.destroy(ctx);
    const buffer = try owner.alloc(u8, 16 * 1024 * 1024);
    errdefer owner.free(buffer);
    ctx.* = .{ .owner = owner, .buffer = buffer, .fixed = .init(buffer), .source = source, .diag = diag };
    ctx.a = ctx.fixed.allocator();
    ctx.source = try ctx.a.dupe(u8, source);
    const tokens = try @import("lexer.zig").lex(ctx.a, ctx.source, diag);
    var parser: s.Parser = .{ .a = ctx.a, .source = ctx.source, .diag = diag, .tokens = tokens };
    ctx.tree = try parser.parse();
    try ctx.lower();
    const assembly = ctx.out.written();
    var ad: asm16.Diagnostic = .{};
    const program = asm16.assemble(ctx.a, assembly, &ad) catch |err| {
        if (ad.line > 0 and ad.line <= ctx.origins.items.len) diag.line = ctx.origins.items[ad.line - 1].line;
        return err;
    };
    // Every instruction in a multi-line emission has the originating source line.
    for (program.locations) |*loc| {
        if (loc.line <= ctx.origins.items.len) {
            const origin = ctx.origins.items[loc.line - 1];
            if (origin.line > 0) {
                loc.line = origin.line;
                loc.column = origin.column;
            } else loc.file = "<n16-runtime>";
        }
    }
    return .{ .context = ctx, .assembly = assembly, .program = program };
}

fn symbolAddress(result: Result, name: []const u8) !u32 {
    for (result.program.symbols) |symbol| if (eq(symbol.name, name)) return @intCast(symbol.value);
    return error.CompilerDebugSymbol;
}
pub fn writeDebugMap(w: *std.Io.Writer, a: std.mem.Allocator, result: Result, file: []const u8) !void {
    const maps = @import("../debug/symbols.zig");
    const locations = try a.alloc(maps.Source, result.program.locations.len);
    defer a.free(locations);
    for (result.program.locations, locations) |loc, *target| target.* = .{ .file = if (loc.file.len > 0) loc.file else file, .address = loc.address, .length = loc.length, .line = loc.line, .column = loc.column };
    const variables = try a.alloc(maps.Variable, result.context.variables.items.len);
    defer a.free(variables);
    var variable_count: usize = 0;
    for (result.context.variables.items, 0..) |variable, index| {
        if (variable.function != none and !result.context.functions.items[variable.function].reachable) continue;
        const target = &variables[variable_count];
        variable_count += 1;
        const ty = result.context.tree.types[variable.ty];
        const element = if (ty.kind == .array) result.context.tree.types[ty.element] else ty;
        target.* = .{ .name = variable.name, .type_name = if (ty.kind == .array) "array" else ty.name, .address = variable.address, .words = ty.words, .frame_relative = variable.function != none, .signed = element.kind == .signed, .constant = variable.constant_value };
        if (variable.function != none) {
            const begin = try std.fmt.allocPrint(a, "_c_v_{d}", .{index});
            defer a.free(begin);
            target.scope_start = try symbolAddress(result, begin);
            const function = result.context.tree.nodes[result.context.functions.items[variable.function].node];
            const end = if (variable.end_block != none) try std.fmt.allocPrint(a, "_c_b_{d}", .{variable.end_block}) else try std.fmt.allocPrint(a, "_c_end_{s}", .{function.token.text});
            defer a.free(end);
            target.scope_end = try symbolAddress(result, end);
        }
    }
    const map: maps.Map = .{ .schema_version = 3, .rom_checksum = std.mem.readInt(u32, result.program.image[12..16], .little), .symbols = result.program.symbols, .locations = locations, .variables = variables[0..variable_count] };
    try std.json.Stringify.value(map, .{}, w);
    try w.writeByte('\n');
}

/// Deterministic size accounting. Entries partition the actual assembled payload;
/// compiler scaffolding includes boot, trap handlers and alignment outside units.
pub fn writeSizeReport(w: *std.Io.Writer, a: std.mem.Allocator, result: Result) !void {
    const Unit = struct { name: []const u8, bytes: usize };
    var functions: std.ArrayList(Unit) = .empty;
    defer functions.deinit(a);
    var libraries: std.ArrayList(Unit) = .empty;
    defer libraries.deinit(a);
    var attributed: usize = 0;
    var removed_functions: usize = 0;
    for (result.context.functions.items) |function| {
        if (!function.reachable) {
            removed_functions += 1;
            continue;
        }
        const name = result.context.tree.nodes[function.node].token.text;
        const begin = try std.fmt.allocPrint(a, "_c_f_{s}", .{name});
        defer a.free(begin);
        const end = try std.fmt.allocPrint(a, "_c_end_{s}", .{name});
        defer a.free(end);
        const bytes = try symbolAddress(result, end) - try symbolAddress(result, begin);
        try functions.append(a, .{ .name = name, .bytes = bytes });
        attributed += bytes;
    }
    const payload = result.program.image.len - 32;
    const blocks = result.context.library_plan.?.blocks;
    var removed: usize = 0;
    for (blocks, 0..) |block, index| {
        if (!block.retained) {
            removed += 1;
            continue;
        }
        const begin = try symbolAddress(result, block.name);
        var end: u32 = @intCast(0xe000 + payload);
        for (blocks[index + 1 ..]) |next| {
            if (next.retained) {
                end = try symbolAddress(result, next.name);
                break;
            }
        }
        const bytes = end - begin;
        try libraries.append(a, .{ .name = block.name, .bytes = bytes });
        attributed += bytes;
    }
    try std.json.Stringify.value(.{
        .schema_version = @as(u16, 1),
        .rom_payload_bytes = payload,
        .rom_capacity_bytes = @as(usize, 8192),
        .rom_percent = @as(f64, @floatFromInt(payload)) * 100 / 8192,
        .static_ram_bytes = result.context.static_end - 0x100,
        .frame_bytes = @as(u16, 256),
        .functions = functions.items,
        .library_blocks = libraries.items,
        .removed_library_blocks = removed,
        .removed_functions = removed_functions,
        .compiler_bytes = payload - attributed,
    }, .{}, w);
    try w.writeByte('\n');
}

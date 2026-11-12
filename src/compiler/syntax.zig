const std = @import("std");
pub const Token = @import("lexer.zig").Token;
pub const Id = usize;
pub const none = std.math.maxInt(Id);
pub const Field = struct { name: Token, ty: Id, offset: u16 };
pub const Type = struct { kind: enum { unsigned, signed, boolean, array, record }, name: []const u8 = "", words: u16 = 1, element: Id = none, length: u16 = 0, fields: []Field = &.{} };
pub const Tag = enum { number, boolean, name, unary, binary, call, index, member, select, decl, assign, expression, ret, conditional, loop, block, function, record };
pub const Node = struct { tag: Tag, token: Token, a: Id = none, b: Id = none, c: Id = none, items: []Id = &.{}, ty: Id = none, binding: Id = none, value: u16 = 0, height: u8 = 1 };
pub const Syntax = struct { nodes: []Node, roots: []Id, types: []Type };
pub const Parser = struct {
    a: std.mem.Allocator,
    source: []const u8,
    diag: *@import("../asm/diagnostic.zig").Diagnostic,
    tokens: []Token,
    pos: usize = 0,
    depth: usize = 0,
    nodes: std.ArrayList(Node) = .empty,
    types: std.ArrayList(Type) = .empty,
    fn peek(self: *Parser) Token {
        return self.tokens[self.pos];
    }
    fn take(self: *Parser) Token {
        const t = self.peek();
        if (t.kind != .eof) self.pos += 1;
        self.diag.* = .{ .token = t.text, .offset = @intFromPtr(t.text.ptr) - @intFromPtr(self.source.ptr), .length = t.text.len, .line = t.line, .column = t.column };
        return t;
    }
    fn eat(self: *Parser, text: []const u8) bool {
        if (!std.mem.eql(u8, self.peek().text, text)) return false;
        _ = self.take();
        return true;
    }
    fn need(self: *Parser, text: []const u8) !void {
        if (!self.eat(text)) {
            self.diag.focus(self.source, self.peek().text);
            return error.ExpectedToken;
        }
    }
    fn name(self: *Parser) !Token {
        const t = self.take();
        if (t.kind != .name) return error.ExpectedIdentifier;
        return t;
    }
    fn node(self: *Parser, input: Node) !Id {
        if (self.nodes.items.len == 8192) return error.AstLimit;
        var n = input;
        for ([_]Id{ n.a, n.b, n.c }) |child| if (child != none) {
            n.height = @max(n.height, self.nodes.items[child].height + 1);
        };
        for (n.items) |child| n.height = @max(n.height, self.nodes.items[child].height + 1);
        if (n.height > 64) return error.NestingLimit;
        try self.nodes.append(self.a, n);
        return self.nodes.items.len - 1;
    }
    fn addType(self: *Parser, ty: Type) !Id {
        if (self.types.items.len == 128) return error.TypeLimit;
        try self.types.append(self.a, ty);
        return self.types.items.len - 1;
    }
    fn typeId(self: *Parser) anyerror!Id {
        self.depth += 1;
        defer self.depth -= 1;
        if (self.depth > 64) return error.NestingLimit;
        if (self.eat("[")) {
            const t = self.take();
            const count = std.fmt.parseInt(u16, t.text, 0) catch return error.ArraySize;
            if (count == 0 or count > 8192) return error.ArraySize;
            try self.need("]");
            const element = try self.typeId();
            if (element > 2) return error.AggregateElement;
            return self.addType(.{ .kind = .array, .words = count, .length = count, .element = element });
        }
        const t = try self.name();
        for (self.types.items, 0..) |ty, id| if (std.mem.eql(u8, ty.name, t.text)) return id;
        return error.UnknownType;
    }
    fn precedence(op: []const u8) u8 {
        const levels = [_][]const []const u8{ &.{"||"}, &.{"&&"}, &.{"|"}, &.{"^"}, &.{"&"}, &.{ "==", "!=" }, &.{ "<", ">", "<=", ">=" }, &.{ "<<", ">>" }, &.{ "+", "-" }, &.{ "*", "/", "%" } };
        for (levels, 1..) |ops, level| for (ops) |text| if (std.mem.eql(u8, op, text)) return @intCast(level);
        return 0;
    }
    fn expression(self: *Parser, minimum: u8) anyerror!Id {
        self.depth += 1;
        defer self.depth -= 1;
        if (self.depth > 64) return error.NestingLimit;
        var left: Id = undefined;
        const token = self.take();
        if (std.mem.eql(u8, token.text, "(")) {
            left = try self.expression(0);
            try self.need(")");
        } else if (token.kind == .number) {
            left = try self.node(.{ .tag = .number, .token = token, .value = std.fmt.parseInt(u16, token.text, 0) catch return error.IntegerRange });
        } else if (std.mem.eql(u8, token.text, "true") or std.mem.eql(u8, token.text, "false")) {
            left = try self.node(.{ .tag = .boolean, .token = token, .value = @intFromBool(std.mem.eql(u8, token.text, "true")) });
        } else if (std.mem.eql(u8, token.text, "-") or std.mem.eql(u8, token.text, "~") or std.mem.eql(u8, token.text, "!")) {
            left = try self.node(.{ .tag = .unary, .token = token, .a = try self.expression(11) });
        } else if (token.kind == .name) left = try self.node(.{ .tag = .name, .token = token }) else return error.ExpectedExpression;
        while (true) {
            if (self.eat("(")) {
                var args: std.ArrayList(Id) = .empty;
                if (!self.eat(")")) while (true) {
                    if (args.items.len == 4) return error.ArgumentLimit;
                    try args.append(self.a, try self.expression(0));
                    if (self.eat(")")) break;
                    try self.need(",");
                };
                left = try self.node(.{ .tag = .call, .token = self.nodes.items[left].token, .a = left, .items = try args.toOwnedSlice(self.a) });
            } else if (self.eat("[")) {
                const index = try self.expression(0);
                try self.need("]");
                left = try self.node(.{ .tag = .index, .token = self.nodes.items[left].token, .a = left, .b = index });
            } else if (self.eat(".")) {
                left = try self.node(.{ .tag = .member, .token = try self.name(), .a = left });
            } else {
                const op = self.peek();
                const p = precedence(op.text);
                if (p == 0 or p < minimum) break;
                _ = self.take();
                const right = try self.expression(p + 1);
                left = try self.node(.{ .tag = .binary, .token = op, .a = left, .b = right });
            }
        }
        if (minimum == 0 and self.eat("?")) {
            const yes = try self.expression(0);
            try self.need(":");
            left = try self.node(.{ .tag = .select, .token = token, .a = left, .b = yes, .c = try self.expression(0) });
        }
        return left;
    }
    fn declaration(self: *Parser, constant: bool) !Id {
        const t = try self.name();
        try self.need(":");
        const ty = try self.typeId();
        const init = if (self.eat("=")) try self.expression(0) else none;
        if (constant and init == none) return error.ConstantInitializer;
        try self.need(";");
        return self.node(.{ .tag = .decl, .token = t, .ty = ty, .a = init, .value = @intFromBool(constant) });
    }
    fn block(self: *Parser) anyerror!Id {
        const token = self.peek();
        try self.need("{");
        self.depth += 1;
        defer self.depth -= 1;
        if (self.depth > 64) return error.NestingLimit;
        var items: std.ArrayList(Id) = .empty;
        while (!self.eat("}")) {
            if (self.peek().kind == .eof) return error.ExpectedToken;
            try items.append(self.a, try self.statement());
        }
        return self.node(.{ .tag = .block, .token = token, .items = try items.toOwnedSlice(self.a) });
    }
    fn statement(self: *Parser) anyerror!Id {
        const t = self.peek();
        if (self.eat("var")) return self.declaration(false);
        if (self.eat("const")) return self.declaration(true);
        if (self.eat("return")) {
            const value = try self.expression(0);
            try self.need(";");
            return self.node(.{ .tag = .ret, .token = t, .a = value });
        }
        if (self.eat("if")) {
            try self.need("(");
            const condition = try self.expression(0);
            try self.need(")");
            const yes = try self.block();
            const no = if (self.eat("else")) try self.block() else none;
            return self.node(.{ .tag = .conditional, .token = t, .a = condition, .b = yes, .c = no });
        }
        if (self.eat("while")) {
            try self.need("(");
            const condition = try self.expression(0);
            try self.need(")");
            return self.node(.{ .tag = .loop, .token = t, .a = condition, .b = try self.block() });
        }
        if (std.mem.eql(u8, t.text, "{")) return self.block();
        const expr = try self.expression(0);
        if (self.eat("=")) {
            const value = try self.expression(0);
            try self.need(";");
            return self.node(.{ .tag = .assign, .token = t, .a = expr, .b = value });
        }
        try self.need(";");
        return self.node(.{ .tag = .expression, .token = t, .a = expr });
    }
    pub fn parse(self: *Parser) !Syntax {
        _ = try self.addType(.{ .kind = .unsigned, .name = "u16" });
        _ = try self.addType(.{ .kind = .signed, .name = "i16" });
        _ = try self.addType(.{ .kind = .boolean, .name = "bool" });
        var roots: std.ArrayList(Id) = .empty;
        while (self.peek().kind != .eof) {
            var root: Id = undefined;
            if (self.eat("struct")) {
                const t = try self.name();
                for (self.types.items) |ty| if (std.mem.eql(u8, ty.name, t.text)) return error.DuplicateType;
                try self.need("{");
                var fields: std.ArrayList(Field) = .empty;
                while (!self.eat("}")) {
                    if (fields.items.len == 16) return error.FieldLimit;
                    const field = try self.name();
                    for (fields.items) |old| if (std.mem.eql(u8, old.name.text, field.text)) return error.DuplicateField;
                    try self.need(":");
                    const ty = try self.typeId();
                    if (ty > 2) return error.AggregateField;
                    try self.need(";");
                    try fields.append(self.a, .{ .name = field, .ty = ty, .offset = @intCast(fields.items.len * 2) });
                }
                if (fields.items.len == 0) return error.EmptyStruct;
                const ty = try self.addType(.{ .kind = .record, .name = t.text, .words = @intCast(fields.items.len), .fields = try fields.toOwnedSlice(self.a) });
                root = try self.node(.{ .tag = .record, .token = t, .ty = ty });
            } else if (self.eat("fn")) {
                const t = try self.name();
                try self.need("(");
                var params: std.ArrayList(Id) = .empty;
                if (!self.eat(")")) while (true) {
                    if (params.items.len == 4) return error.ArgumentLimit;
                    const arg = try self.name();
                    try self.need(":");
                    const ty = try self.typeId();
                    if (ty > 2) return error.AggregateParameter;
                    try params.append(self.a, try self.node(.{ .tag = .decl, .token = arg, .ty = ty }));
                    if (self.eat(")")) break;
                    try self.need(",");
                };
                try self.need("->");
                const ty = try self.typeId();
                if (ty > 2) return error.AggregateReturn;
                root = try self.node(.{ .tag = .function, .token = t, .ty = ty, .items = try params.toOwnedSlice(self.a), .a = try self.block() });
            } else if (self.eat("var")) root = try self.declaration(false) else if (self.eat("const")) root = try self.declaration(true) else return error.ExpectedDeclaration;
            try roots.append(self.a, root);
        }
        return .{ .nodes = try self.nodes.toOwnedSlice(self.a), .roots = try roots.toOwnedSlice(self.a), .types = try self.types.toOwnedSlice(self.a) };
    }
};

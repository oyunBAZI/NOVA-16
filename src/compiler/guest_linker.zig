//! Reachability for the reviewed, position-independent ABI1 guest library.
//! Uses assembler syntax, exact operand symbols and explicit fallthrough edges.
//! This is deliberately not a general-purpose assembly garbage collector.
const std = @import("std");
const parser = @import("../asm/parser.zig");
const lex = @import("../asm/lexer.zig");

pub const Block = struct {
    name: []const u8,
    start: usize,
    end: usize,
    retained: bool = false,
};
pub const Plan = struct {
    blocks: []Block,
    allocator: std.mem.Allocator,
    pub fn deinit(self: Plan) void {
        self.allocator.free(self.blocks);
    }
};

fn reference(arg: []const u8) ?[]const u8 {
    // Assembler expressions allow an atom followed by one numeric +/- suffix.
    var end = arg.len;
    for (arg, 0..) |c, i| {
        if (c == '+' or c == '-') {
            end = i;
            break;
        }
    }
    const atom = lex.trim(arg[0..end]);
    return if (lex.identifier(atom)) atom else null;
}

fn mark(symbols: *const std.StringHashMap(usize), blocks: []Block, name: []const u8) bool {
    if (symbols.get(name)) |index| {
        if (!blocks[index].retained) {
            blocks[index].retained = true;
            return true;
        }
    }
    return false;
}

pub fn plan(a: std.mem.Allocator, roots: []const u8, library: []const u8) !Plan {
    var blocks: std.ArrayList(Block) = .empty;
    errdefer blocks.deinit(a);
    var symbols = std.StringHashMap(usize).init(a);
    defer symbols.deinit();
    var lines = std.mem.splitScalar(u8, library, '\n');
    var offset: usize = 0;
    while (lines.next()) |line| {
        const parsed = try parser.parse(line);
        if (parsed.label) |label| {
            if (symbols.contains(label)) return error.DuplicateLibrarySymbol;
            if (blocks.items.len > 0) blocks.items[blocks.items.len - 1].end = offset;
            try symbols.put(label, blocks.items.len);
            try blocks.append(a, .{ .name = label, .start = offset, .end = library.len });
        } else if (blocks.items.len == 0 and parsed.name.len != 0) return error.LibraryPreamble;
        offset += line.len + 1;
    }
    // Root references are parsed from the already lowered, type-checked program.
    lines = std.mem.splitScalar(u8, roots, '\n');
    while (lines.next()) |line| {
        const parsed = try parser.parse(line);
        const args = try lex.operands(parsed.args);
        for (args.items[0..args.len]) |arg| if (reference(arg)) |name| {
            _ = mark(&symbols, blocks.items, name);
        };
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (blocks.items, 0..) |block, index| {
            if (!block.retained) continue;
            var body = std.mem.splitScalar(u8, library[block.start..block.end], '\n');
            var terminal = false;
            while (body.next()) |line| {
                const parsed = try parser.parse(line);
                if (parsed.name.len == 0) continue;
                // Reject new location-dependent layouts rather than silently
                // making an unsupported pruning decision.
                if (parsed.name[0] == '.' and !std.ascii.eqlIgnoreCase(parsed.name, ".byte") and !std.ascii.eqlIgnoreCase(parsed.name, ".align")) return error.UnsupportedLibraryDirective;
                if (std.ascii.eqlIgnoreCase(parsed.name, "JMPR") or std.ascii.eqlIgnoreCase(parsed.name, "CALLR")) return error.UnsupportedLibraryControlFlow;
                const args = try lex.operands(parsed.args);
                for (args.items[0..args.len]) |arg| if (reference(arg)) |name| {
                    changed = mark(&symbols, blocks.items, name) or changed;
                };
                const branch = std.ascii.eqlIgnoreCase(parsed.name, "JMP") or std.ascii.eqlIgnoreCase(parsed.name, "CALL") or std.ascii.startsWithIgnoreCase(parsed.name, "B.");
                if (branch and (args.len != 1 or !symbols.contains(args.items[0]))) return error.UnsupportedLibraryControlFlow;
                terminal = std.ascii.eqlIgnoreCase(parsed.name, "RET") or std.ascii.eqlIgnoreCase(parsed.name, "HALT") or std.ascii.eqlIgnoreCase(parsed.name, "JMP") or std.ascii.eqlIgnoreCase(parsed.name, "B.AL");
            }
            // Calls and conditional branches return/fall through. Labels may
            // denote shared tails; keeping the next block handles both cases.
            if (!terminal and index + 1 < blocks.items.len and !blocks.items[index + 1].retained) {
                blocks.items[index + 1].retained = true;
                changed = true;
            }
        }
    }
    return .{ .blocks = try blocks.toOwnedSlice(a), .allocator = a };
}

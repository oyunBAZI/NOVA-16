const std = @import("std");
pub const Diagnostic = struct {
    line_starts: []const usize = &.{},
    line: usize = 1,
    column: usize = 1,
    offset: usize = 0,
    length: usize = 0,
    token: []const u8 = "",
    reason: []const u8 = "",
    code: []const u8 = "",
    pub fn focus(self: *Diagnostic, source: []const u8, token: []const u8) void {
        const base = @intFromPtr(source.ptr);
        const ptr = @intFromPtr(token.ptr);
        if (ptr < base or ptr > base + source.len) return;
        self.offset = ptr - base;
        self.length = token.len;
        self.token = token;
        if (self.line_starts.len > 0) {
            var low: usize = 0;
            var high = self.line_starts.len;
            while (low + 1 < high) {
                const mid = low + (high - low) / 2;
                if (self.line_starts[mid] <= self.offset) low = mid else high = mid;
            }
            self.line = low + 1;
            self.column = self.offset - self.line_starts[low] + 1;
            return;
        }
        self.line = 1;
        self.column = 1;
        for (source[0..self.offset]) |c| {
            if (c == '\n') {
                self.line += 1;
                self.column = 1;
            } else self.column += 1;
        }
    }
    pub fn explain(self: *Diagnostic, err: anyerror) void {
        self.code = @errorName(err);
        self.reason = switch (err) {
            error.UndefinedSymbol => "symbol is not defined",
            error.DuplicateSymbol => "symbol is already defined",
            error.ExpectedRegister => "expected register R0 through R7",
            error.ExpectedMemory => "expected [base register +/- byte displacement]",
            error.DisplacementRange => "memory displacement must be -32 through +31 bytes",
            error.InvalidTarget => "control target must be an even executable RAM or ROM address",
            error.BadEntry => "entry must be even and inside the emitted ROM payload",
            error.BadAlignment => ".align requires a positive power of two",
            error.UnknownMnemonic => "unknown ISA V1 instruction mnemonic",
            error.UnknownDirective => "unknown assembly directive",
            error.Syntax => "unbalanced quotes/brackets, empty operand or invalid punctuation",
            error.Width => "expression exceeds the allowed numeric range",
            error.BranchRange => "branch target must be within -128 to +127 instruction words",
            error.CyclicConstant => "constant depends on a cyclic chain",
            error.OperandCount => "instruction or directive has the wrong number of operands",
            error.InvalidNumber => "invalid or overflowing numeric literal",
            error.ExpectedExpression => "expected a literal or symbol, optionally followed by + or - and a number",
            else => @errorName(err),
        };
    }
};

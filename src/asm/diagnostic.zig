const std = @import("std");
pub const Diagnostic = struct {
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
        self.reason = if (err == error.UndefinedSymbol) "symbol is not defined" else if (err == error.DuplicateSymbol) "symbol is already defined" else if (err == error.ExpectedRegister) "expected register R0 through R7" else if (err == error.Width) "expression exceeds the allowed numeric range" else if (err == error.BranchRange) "branch target must be within -128 to +127 instruction words" else if (err == error.CyclicConstant) "constant depends on a cyclic chain" else if (err == error.OperandCount) "instruction or directive has the wrong number of operands" else if (err == error.InvalidNumber) "invalid or overflowing numeric literal" else if (err == error.ExpectedExpression) "expected a literal or symbol, optionally followed by + or - and a number" else @errorName(err);
    }
};

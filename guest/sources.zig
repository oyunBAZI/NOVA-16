pub const arithmetic = @embedFile("lib/arithmetic.asm");
pub const memory = @embedFile("lib/memory.asm");
pub const graphics = @embedFile("lib/graphics.asm");
pub const runtime = @embedFile("lib/runtime.asm");
pub const font = @embedFile("lib/font.asm") ++ @embedFile("lib/font_data.asm");
pub const all = arithmetic ++ memory ++ graphics ++ runtime ++ font;

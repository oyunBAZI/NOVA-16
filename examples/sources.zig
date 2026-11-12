pub const splash = @embedFile("boot_splash.asm");
pub const bouncing = @embedFile("bouncing_pixel.asm");
pub const paint = @embedFile("paint.asm");

pub const diagnostics = @embedFile("diagnostics.asm");

pub const breakout = @embedFile("projects/breakout/constants.asm") ++
    @embedFile("projects/breakout/entry.asm") ++
    @embedFile("projects/breakout/game.asm") ++
    @embedFile("projects/breakout/graphics.asm") ++
    @embedFile("projects/breakout/font.asm");

pub const abi = @embedFile("abi_conformance.asm");

# Bootable ROMs
`zig build` builds all four assembly sources into `zig-out/demos/NAME.n16`
and `.sym`. `zig build demos` assembles just the ROMs. No image is painted by
special host code: every VRAM/palette modification is a guest store.

| ROM | Behavior and expected output |
|---|---|
|boot_splash|Tiled blue/purple field, diamond and ROM-font NOVA-16; HALT after 84,138 instructions; VRAM CRC32 136947820|
|bouncing_pixel|4×4 yellow ball; FRAME polling; reverses at x=0/124,y=0/92; after 140 frames x=32,y=44|
|paint|Arrows move; Z paints, X erases, Enter clears; starts at x=64,y=48; reversible blue cursor byte overlay|
|diagnostics|ALU/flags/endian/load/store/stack/nested calls/shifts/logic checks; green on pass, red on fail|

Diagnostics success: R7=0x600D, R6=2, SP=0xBFFE, R0=0xD800,
R1=0x00BB, no trap, HALT after 24,644 instructions. All 6144 VRAM bytes are BB.
VRAM CRC32=892659172. PPM SHA-256:
`b46b81b0ff39fe8e0e92b2ffd76c0107835e577e17d2f1e050adfea043ea3df6`.
Failure: R7=DEAD, VRAM all 66. Integration tests deliberately mutate an input
to exercise this path without modifying the emulator.

Paint preserves adjacent nibbles, clamps at every edge, gives erase precedence
over paint, and clears on the Start rising edge. A paused debugger does not
advance frame time. Use the runner for frame-dependent animation/input.

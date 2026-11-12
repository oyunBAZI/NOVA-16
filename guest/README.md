# Guest standard library, ABI1 revision 1

Include needed modules with `.include "lib/arithmetic.asm"` etc, inside a
configured project root containing guest/. Definitions use the `n16_` prefix.
Place the program entry/HALT before library definitions or select `.entry`.
`guest/sources.zig` is the same source embedded into compiler/tests, not a host
implementation of these routines. All work is performed by original V1 opcodes.
Existing Breakout source/ROM is retained; the generic font routines adapt its
original glyph design and packed-pixel logic into the documented ABI.

All routines preserve R4–R7 and real SP on return. R0–R3/flags are caller-saved,
including argument registers not explicitly returned. Unless stated otherwise,
there is no RAM scratch. Integer values wrap in 16 bits. No heap or host calls.
The implementation has bounded loops (division 16 steps; copy/clear <=65535
bytes, framebuffer <=6144 bytes; drawing <=128×96; decimal <=5 digits).

| Entry | R0,R1,R2,R3 input | Output / supported limits |
|---|---|---|
|n16_udiv|numerator, divisor|R0 quotient, R1 remainder, R2=0; divisor0 R2=1|
|n16_sdiv|signed numerator, divisor|Truncate toward zero; remainder sign of numerator; R2=1 zero, 2 MIN/-1 wrapped overflow|
|n16_umod / n16_smod|numerator, divisor|R0 remainder, R2 status as division|
|n16_ucmp / n16_scmp|left, right|R0=-1/0/1 using unsigned/signed ordering|
|n16_uadd_checked / n16_sadd_checked|left, right|R0 wrapping sum; R2=overflow|
|n16_usub_checked / n16_ssub_checked|left, right|R0 wrapping difference; R2=borrow/signed overflow|
|n16_umul_checked|left,right|R0 low product; R2=unsigned overflow|
|n16_u8_checked|value|Unchanged R0; R2=1 if >255|
|n16_unsigned_checked|i16 value|R2=1 if negative; unchanged R0|
|n16_signed_checked|u16 value|R2=1 if >32767; unchanged R0|
|n16_bool|value|R0 normalized 0/1|
|n16_memzero|destination, byte count|R3=0/1; destination whole range must be RAM/VRAM|
|n16_memcopy|destination, source, byte count|Overlap-safe memmove; R0 original dst, R3=0/1; src RAM/VRAM/ROM, dst RAM/VRAM|
|n16_load_word|address|R0 value, R3=0/1; aligned RAM/VRAM/ROM, no MMIO|
|n16_store_word|address,value|R3=0/1; aligned RAM/VRAM only|
|n16_array_get|base,index,count|R0 value/R3 status; index<count<=8192, checked word address|
|n16_array_set|base,index,count,value|R3 status; validates before write|
|n16_color|palette index|Masks low4 bits; scratch E0–E1 selected color|
|n16_pixel|x,y,index|R3=0/1; x<128,y<96; low4 color bits; preserves neighbouring nibble|
|n16_rect|x,y,width,height|Uses selected color; clips right/bottom; fully clipped/empty no-op; R3=0|
|n16_clear|palette index|Fills all VRAM in <=12500 instructions|
|n16_bitmap / n16_sprite|x,y,source,(height<<8)\|width|Opaque byte-per-pixel indices; width<=128,height<=96; source range preflight; R3 status|
|n16_glyph|x,y,ASCII|3×5 clipped glyph; ASCII32–90; selected color; R3 status|
|n16_number|x,y,value|Unsigned decimal, <=5 digits; selected color; R3 status|
|n16_palette|index,r,g,b|Index<16/RGB<=255 checked before any change; R0 status|
|n16_buttons|none|R0 sampled held buttons|
|n16_input_poll|none|R0 held,R1 latched pressed(read-clear),R2 sampled releases; E2–E3 previous held|
|n16_frame|none|R0 frame counter|
|n16_wait_frame|previous counter|R0 next different counter; guest waits until host requests next frame|
|n16_random|caller-owned seed|R0 = seed*25173+13849 modulo65536; caller stores next seed|
|n16_counter|counter, nonzero period|R0 incremented counter or0 on reaching period|

Graphics bitmap aliases are opaque; transparency is not promised. Sources must
not overlap their destination. Pixel/rectangle coordinates are unsigned; negative
values represented as FFFF clip out, not wrap into VRAM. A complete source range
is checked even for clipped bitmap pixels. Fonts depend on graphics+arithmetic
and font_data; no routine copies code or renders from the host. Clear/new screens
can span guest frames; callers use sampled/latching input appropriately.

Memory helpers reject MMIO to avoid incidental read-clear effects. Empty ranges
are no-ops. Failure status leaves destination bytes unchanged; caller-saved
registers and documented scratch may change. Hardware traps still enforce ISA
permissions if assembly bypasses these routines. Compiler raw peek/poke builtins
are explicit device access, distinct from checked library memory functions.

Executable tests in src/guest_library_tests.zig assemble real ROMs, run CPU
instructions and verify independent arithmetic oracles, status, memory/graphics,
input, caller-owned randomness, stack and saved-register sentinels.

Profile2 assembly helpers live in `v2.asm`: `n16v2_voice` programs one voice
while disabled; `n16v2_timer` rearms the timer with explicit split writes. Register
contracts are documented at each routine. The two V2 demonstration projects
carry identical copies so projects/packages stay self-contained. These helpers
require explicit V2 assembly; N16C remains a V1 compiler.

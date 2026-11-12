# Write and ship your first NOVA-16 program

Install a native release package (INSTALL.md); the three binaries are independent
of Zig/SDL2. Source builds require exactly Zig 0.17.1. The following commands run
from the repository root; Windows uses `bin\*.exe` in an extracted package.
Python 3.12 is needed only for the optional test/package helper scripts.

## Create and build
Copy `examples/projects/counter` to a new directory, e.g. `my-game`. Its main.asm
includes routines using paths relative to each containing file. All symbols share
one namespace; name routines explicitly. Build with one command:

```sh
zig-out/bin/n16asm my-game/main.asm --project-root my-game --out zig-out/my-game.n16 --debug-symbols zig-out/my-game.sym2 --listing zig-out/my-game.lst
zig-out/bin/nova16 inspect zig-out/my-game.n16 --json
zig-out/bin/nova16 run zig-out/my-game.n16 --headless --frames 120 --screenshot zig-out/my-game.ppm
```

The CPU fetches a little-endian instruction, decodes its 2/4-byte form, executes
it and retires it. General registers R0–R7 hold 16-bit values. Z/N/C/V describe
ALU results; conditional branches test them. CALL/RET use the checked RAM stack.
Consult isa.md for operand widths, signed displacements and flag semantics.
The counter sets R1=42, stores a word to RAM 0100, displays byte 2A at C000 and
halts. These effects are actual guest instructions, not host rendering.

RAM 0000–BFFF is writable/executable. ROM E000–FFFF is executable/read-only,
8 KiB maximum. VRAM C000–D7FF contains packed display pixels: byte offset
`y*64 + x/2`, even X in the low nibble. A byte `0x2A` displays palette color A
then 2. Never execute VRAM/MMIO. Words must be even-aligned.

MMIO D800 is held buttons; D801 is latched presses and clears on read.
D802/D803 give the frame counter; D805 acknowledges vblank on read. Palette
RGB bytes start at D820, and D804 controls video enable. `memory-map.md` lists
all valid addresses; other device accesses trap. Input bits: Up=1, Down=2,
Left=4, Right=8, A=16, B=32, Start=64, Select=128. GUI arrows/Z/X/Enter map to these.
A host frame provides at most 20,000 instructions; use a frame counter wait for
stable animation. Host timers only pace graphical presentation.

## Debug

```sh
zig-out/bin/n16dbg zig-out/my-game.n16 --symbols zig-out/my-game.sym2
```

Enter `break lib/graphics.asm:2`, `continue 100`, `regs`, `source`, `next`,
`mem result 2`. Use `history 8`, `step`, `reverse` to undo one recorded instruction.
`savesnap state.n16s`, `step`, `loadsnap state.n16s` restores deterministic state;
loading clears undo history. A snapshot is bound to ROM identity. Preserve source
maps with the ROM; the debugger rejects checksum mismatches. Fault reports show
PC, instruction, disassembly, access/address and mapped file/line. Fix the source,
rebuild, reload: reset clears writable state but does not clear a code defect.

## Test and replay
Save this JSON in `zig-out/counter-test.json`:

```json
{"schema_version":1,"rom":"my-game.n16","frames":120,"registers":{"1":42},"halted":true}
```

```sh
python3 scripts/rom_test.py zig-out/counter-test.json
```

Test schema 1 accepts rom, frames (0–10000), optional input schedule path,
register-index/value checks, halted and ppm_sha256. Paths are relative to the
test file. Failure exits nonzero; success emits report JSON schema 1 with actual
State JSON V1 and framebuffer hash. Add an expected hash after reviewing output.
For a replay, save `0 8`, `20 0` on separate lines in a schedule (hold Right
from frame 0 through 19). Pass `--input schedule.txt` to nova16, or add the
relative `input` field to a test. Identical ROM/input/frame caps reproduce output.

## Distribute

```sh
python3 scripts/guest_package.py my-game --out zig-out/my-game.zip
```

This builds from source and packs program.n16, program.sym2, original .asm files
and guest-manifest.json schema 1 with per-file SHA256. Sorted entries, fixed
metadata and root-relative paths make repeated archives byte-identical. Extract
and run `nova16 run program.n16`; rebuild `src/main.asm --project-root src` to
verify the ROM. Shared binary hashes provide integrity, not code signing.
Assembly errors leave the previous ROM intact. A nonzero command exit must fail
your automation; never treat a stale ROM left after failed assembly as a new build.

# NOVA-16 — nova16-virtual-computer

A complete, understandable fictional 16-bit computer built in **Zig 0.17.1**.
A deterministic CPU, its own assembler and ROM format, a terminal debugger, and
an optional SDL2 display run real guest assembly programs.

![Guest-generated NOVA-16 boot splash, nearest-neighbor 4x enlargement](docs/splash.png)

## What works

- Eight 16-bit registers, separate PC/SP, Z/N/C/V flags; strict 2/4-byte ISA.
- Full ALU, conditions, calls, checked stack, RAM execution and explicit traps.
- 64 KiB bus, protected ROM, packed 128×96 16-color video, palette/input MMIO.
- Two-pass assembler with labels, expressions, directives and symbol maps.
- Lossless disassembly; debugger with stepping, breakpoints and write watchpoints.
- Bounded headless runs, reproducible JSON and PPM output, scripted input replay.
- Optional SDL2 nearest-neighbor GUI, keyboard controls, pause and reset.
- Four bootable ROMs: splash, bouncing ball, interactive paint and diagnostics.
- Exhaustive decoder/round-trip coverage, independent ALU oracles, fault/property
  tests and black-box CLI acceptance. No external emulator or assembler core.

All phases 0–10 have local acceptance evidence in [the milestone ledger](docs/roadmap.md).
This is an original virtual machine, not an x86 PC, silicon design, OS or
cycle-accurate emulator. Audio, networking, filesystem and multitasking are out of V1 scope.

## Quick start

Install the **exact Zig 0.17.1** release from [ziglang.org](https://ziglang.org/download/).
Headless builds need no third-party library. Linux x86_64 is tested; native
macOS/Windows source builds are intended but have not been verified in this session.

```sh
git clone https://github.com/oyunBAZI/NOVA-16.git
cd NOVA-16
zig version                    # 0.17.1
zig build                      # all three CLIs and four ROMs/symbol maps
zig build test
zig build fmt
python3 scripts/acceptance.py   # black-box acceptance; Python 3 standard library
```

```sh
zig-out/bin/n16asm examples/boot_splash.asm --out zig-out/splash.n16 --symbols zig-out/splash.sym
zig-out/bin/nova16 inspect zig-out/splash.n16
zig-out/bin/nova16 run zig-out/splash.n16 --headless --frames 120 --screenshot zig-out/splash.ppm --state-json zig-out/splash.json
zig-out/bin/n16dbg zig-out/splash.n16
```

The screenshot comes entirely from the assembled guest's VRAM and palette writes.
No ROM-name checks or host-side demo drawing exist.

## Graphical mode

Install SDL2 development libraries (`sudo apt-get install libsdl2-dev` on
Debian/Ubuntu), then:

```sh
zig build -Dgui=true
zig-out/bin/nova16 run zig-out/demos/paint.n16 --gui --scale 4 --frames 100000 --max-instructions 1000000000
```

On macOS with Homebrew SDL2, try `zig build -Dgui=true --search-prefix "$(brew --prefix sdl2)"`.
That platform is untested. [GUI details and validation](docs/gui.md).

| Host key | Guest input / action |
|---|---|
|Arrows|Up/Down/Left/Right|
|Z / X|A (paint) / B (erase)|
|Enter / Right Shift|Start (clear) / Select|
|Space / R / Escape|Host pause / reset / quit|

GUI defaults to 512×384 (4×) and aims for 60 presentations per second.
A guest frame is **20,000 retired instructions**, independent of host clock speed.
Both runners have finite default frame/instruction limits. GUI HALT keeps the
last picture visible until the presentation limit or quit.

## Architecture at a glance

| Address range | Region | Permissions |
|---|---|---|
|0000–BFFF|48 KiB RAM and downward stack|RWX|
|C000–D7FF|6 KiB packed framebuffer|RW|
|D800–DFFF|Whitelisted device registers|Per register|
|E000–FFFF|8 KiB boot ROM|RX|

ISA: MOV/LDI; ADD/SUB/AND/OR/XOR/CMP; LDW/STW/LDB/STB; 15 branch conditions;
JMP/CALL/JMPR/CALLR; shifts, NOT/MUL/TEST/ADDI/CMPI/INC/DEC; PUSH/POP and
PUSHF/POPF; NOP/HALT/BRK/RET. Instructions are even-aligned, words little-endian.
Reserved encodings and illegal memory accesses trap cleanly.

## Documentation and development

[Architecture](docs/architecture.md) · [ISA](docs/isa.md) ·
[Memory/MMIO](docs/memory-map.md) · [ROM format](docs/rom-format.md) ·
[Assembler](docs/assembler.md) · [Debugger](docs/debugger.md) ·
[Video](docs/video.md) · [Examples and hashes](docs/examples.md) ·
[JSON/replay](docs/state-json.md) · [Test vectors](docs/test-vectors.md) ·
[Decisions](docs/decisions.md) · [Development/releases](docs/development.md)

Build a release with `zig build -Doptimize=ReleaseSafe`. CI builds headless and
SDL2 variants, tests the core, assembles ROMs, runs acceptance, and smoke-tests
SDL under Xvfb. Source is intentionally smaller than the illustrative LOC budget;
shared tables and focused tests avoid duplicated code and artificial padding.

Original code: [MIT license](LICENSE). SDL2 retains its zlib license.

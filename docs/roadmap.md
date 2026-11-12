# Milestone ledger

Phases 0–10: pending verification. No completion claims before successful gates.

## Phase 0 — passed
Zig 0.17.1: `zig build`, `zig build test`, and `zig-out/bin/nova16`
all returned exit 0. The executable printed “NOVA-16 virtual computer”.
Build tasks include test and fmt. Headless has no external dependencies.

## Phase 1 — passed
`zig build test` and `zig build` returned exit 0. Raw-byte tests prove reset,
NOP/HALT PC stepping, stopped retirement, malformed opcodes, alignment, and
execute permissions. Decoder enumerates all 65,536 first words.

## Phase 2 — passed
`zig build test` returned exit 0. Implemented all ALU/control/stack operations
and data-transfer dispatch. Boundary arithmetic uses independent signed/wide
oracles; tested all flag/condition combinations, nested calls, invalid CALL
atomicity, empty stack, shift counts 0/1/15. Bus/MMIO hardening follows in phase 3.

## Phase 3 — passed
`zig build test` (13 tests) and `zig build` returned exit 0. Strict region/MMIO
permissions, read-clear devices, ROM parser/packer, CRC, reset, and encoded
boot-to-RAM-write integration pass. Mutation tests reject every changed header
or payload byte; access tests cover all region boundaries.

## Phase 4 — passed
`zig build`, `zig build test` returned exit 0. Two-pass assembly, expressions,
all directives, symbols, negative diagnostics and the n16asm CLI work.
Exhaustive legal-word disassemble/reassemble tests preserve instruction bytes,
including negative offsets and unknown-data fallbacks. Golden forward-reference
bytes match the manual encoding. No external assembler is used.

## Phase 5 — passed
`zig build test`, `zig build`, actual `n16asm` and `nova16 run` pass.
Splash retires 70,481 instructions, HALTs, CRC32(VRAM)=249464469.
PPM SHA-256 is recorded in video.md and asserted in the boot integration test.
Nibble endpoints, palette changes, disable behavior, dimensions and deterministic
PPM bytes pass. Frame scheduling is implemented in the next phase.

## Phase 6 — passed
`zig build test`, `zig build`, assembly of animation/paint and a 60-frame
scripted CLI paint run returned exit 0. Both guests execute 140-frame
replay tests with identical CPU/full memory state. Ball boundary reversal
ends at x/2=16,y=44. Paint input differs from idle output. VBLANK read-clear,
key edges and ordered input schedules pass. Frame budget is 20,000 retired
instructions with an overall cap.

## Phase 7 — passed
GUI build (`zig build -Dgui=true --search-prefix /tmp/nova-host`), dummy-driver
smoke and core tests passed. Real SDL windows were inspected using the desktop:
512×384 splash, moving ball, keyboard paint stroke and clean Escape shutdown.
Host-only pause/reset/pacing and integer texture scaling are implemented.
The default headless build requires no SDL library. See gui.md for dependencies.

## Phase 8 — passed
`zig build test` and `zig build` passed. Scripted debugger unit tests prove
pre-execution breakpoints, watch old/new values, BRK advance/resume, stack and
reset. A piped n16dbg CLI session exercised help, regs, break, continue, step,
mem, disasm with symbols, stack, watch, saveframe, reset and quit; exit 0.

## Phase 9 — passed
`zig build` assembles all four ROMs and symbol maps by default; `zig build test`
passes guest boot integration, golden splash/diagnostic SHA-256, deterministic
motion/input, paint draw/erase/clear/bounds and forced diagnostic failure tests.
Splash now includes a ROM-font wordmark and corrected packed multicolor tiles;
its current hash supersedes the phase 5 image, documented in video.md.

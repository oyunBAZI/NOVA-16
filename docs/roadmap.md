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

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

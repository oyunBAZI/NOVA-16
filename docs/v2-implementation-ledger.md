# NOVA-16 V2 implementation ledger

## Starting point — 2026-11-12

Clean `main` at `a25afb5d72dbd0d0a2afd27409c84d112ccb35d0`, exactly the
historical audited baseline. No later source changes or open issues/PRs were
returned during reconnaissance. GitHub CI43202982980 for that commit completed
successfully. Latest published prerelease remained v0.4.0-rc.1. No release tags
are modified by this work. Work proceeds on `feat/v2-hardware` per CONTRIBUTING.

Exact Zig0.17.1 was already installed and verified. The first build-runner compile
took94.435s; subsequent baseline build1.138s. Debug94/94 and ReleaseSafe94/94,
model4/4 and every requested Python suite passed, including all ten application
replays and all five original ROM byte identities. Full baseline commands,
outputs and elapsed times: `reliability/v2-baseline.json`. These build/test timings
are not comparable CPU-performance claims. Historical component measurements
remain in the v0.4 performance report.

Read revision2 architecture/binary contracts, independent fixtures, roadmap,
architecture/ISA/memory/snapshot/testing/report documents and contribution policy.
Existing executable V2 support consisted only of the isolated audio arithmetic
experiment. Runtime dependencies: Machine→CPU/Bus; Bus→video/input; assembler→
encoder/ISA/ROM; snapshot/debugger/history→Machine; CLI/SDL→core with host I/O
outside core. Compiler, guest ABI/library and project workflow remain V1 unless
explicitly described below.

## Implemented vertical slices

| Slice | Executable changes | Evidence |
|---|---|---|
|Profiles|ROM2 envelope/profile/features validation, default V1, explicit assembler/disassembler selection|Independent ROM bytes; malformed activation atomicity; all65536 decode words|
|Clock|Shared transition scheduler; idle/fault ticks; separate retirement/entry/slot counters; partial/full frames and overflow|24/25 and19999/20000 tests; exact independently generated snapshots|
|Sound|Four integer voices, strict MMIO, mute/reset/phase/LFSR rules, bounded PCM and WAV|Complete independent800-sample hash and guest WAV replay|
|Timer/IRQ|Blocking IRQ mask, W1C, timer split-write rearm, priority, EI/DI/IRET and8-deep checked stack frames|Guest timer execution, independent timer traces/model, nested/invalid return/entry tests|
|State|Exact N16S2 directory/sections/CRCs, cross-field checks, atomic candidate restore|Both unchanged independent fixtures produced from live hardware, exact reencode, corruption and allocation tests|
|Tools|V2 inspect/State JSON2, source maps, device inspector, IRQ trace, full-state reverse, manifest2 assembly projects|Black-box breakpoint/reverse/snapshot tests; unit exact restoration at audio/IRQ/frame boundaries|
|Demos|NOVA Sound and Interrupt Canvas; shared guest helpers copied into self-contained projects|Real guest-generated melody/PCM/PPM; replay hashes in reliability/v2-demonstrations.json|
|Playback|Optional exact-format SDL queued sink,4-frame cap, pause/reset clearing, failure isolation|Real SDL dummy-audio queue/underflow test plus existing events/scaling/all-pixel readback|
|Distribution|New demos/maps/WAVs, profile metadata, extracted V2 acceptance and expanded native CI|Local package and native CI gates recorded below|

D951 follows the normative word "unmasked": a set bit blocks that IRQ;
`eligible = pending & ~mask & 3`. Initial implementation review caught and
corrected the opposite polarity before committing. No independent fixture or
V1 golden changed. Initial V2 demo reference recording happened only after this
correction, before publication; CI never records/rewrites those hashes.

V1 shares CPU execution handlers without copying the emulator. Only ROM2 selects
new decoding/MMIO/scheduling. V1 State JSON1 and N16S1 bytes are unchanged. New
trap codes use their specified12–15 numbering only in N16S2. New device writes
validate both permissions then stage candidate devices before commit. IRQ entry
preflights nesting, target and all stack capacity before writing six bytes.
IRET validates complete saved state before popping. Failures retain architectural
state except specified diagnostic and subsequent slot-end events.

## Verification checkpoint

Expanded Debug suite:116/116 passing. The two demos pass black-box PCM/PPM and
source-debug/reverse checks. Actual SDL2 ABI/events/controls/scaling/readback and
queued-audio tests pass locally with genuine SDL2 2.32.4. Current-source Debug/ReleaseSafe116/116, all original V1 suites in both executable
modes, V2 black-box checks, model tests, security and SDL tests passed locally.
Native Linux and Windows x64/macOS ARM64/macOS x64 cross builds produced identical
nine ROMs. SDK exact-byte reproducibility and extracted-package V1/V2 acceptance
passed with source frozen (`reliability/v2-package.json`). The initial packaging
comparison was invalid because the progress collector edited its own tracked
source report between builds; this is recorded, not hidden. Native remote CI
remains pending, so the complete V2 release gate is not yet claimed.

## Limits and follow-on work

Full machine-copy history remains bounded to32 states. No delta engine is
substituted based on capture-only estimates. Shared V2 serialization currently
uses a bounded temporary V1 metadata/memory encoding to reuse the established
validator; it does not expose or accept an intermediate V1 snapshot as V2.
N16C remains V1/single-unit, all guest library linking remains unchanged. No
compiler/linker optimization, NOVA Studio, V3, FPGA or host-filesystem device is
claimed. V2 uses the reviewed8KiB ROM and128×96 display. No published V2 release
or merge is implied by branch verification.

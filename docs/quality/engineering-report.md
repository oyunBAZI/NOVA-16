# Workbench reliability and integration engineering report

The quality milestone makes the existing machine/toolchain usable across editor,
controller, rewind, import, playback and process/Worker failure boundaries. It
preserves V1/V2 hardware, ROM/snapshot formats, compiler language contracts and
all original golden fixtures. [Plan](plan.md), [review notes](review.md) and the
updated [manual](../workbench.md) describe the scope and interfaces.

## Delivered behavior

- Resume plus the first instruction is one exact undo action. Reversing a step,
  continue or source-next from guest BRK restores the original paused state, in
  full and delta history. Zero budgets and existing embedding groups are covered.
- The editor overlay has independent geometry and scroll alignment. Large valid
  source does not allocate a gutter element per line. Built-source identity
  includes text, architecture and optimization; edits/undo and in-flight builds
  cannot leave false source-line marks. Source imports and local draft recovery
  retain independent editor/VM ownership. Startup waits before enabling editing;
  an unavailable VM still exposes an existing draft for export.
- Keyboard keys and pointers own controller bits independently. Losing one owner
  cannot release another; indicators reflect actual guest state, including rewind
  and snapshot restoration. Blur/capture-loss/background paths release controls.
- Continuous playback sends each actual completed PCM frame once; observations, snapshots
  and controller responses cannot repeat it. Activation failures close their
  candidate context and an open context can be muted after loading V1.
- User `.n16` cartridges are bounded and validated before replacement. Bad CRCs,
  truncation, invalid encoding and failed native child startup retain the working
  VM and last exportable ROM. Native child cleanup cannot mask the original pipe
  failure. Source and ROM imports never silently replace one another.
- Native/offline replay share a grammar corpus and report actual completed
  frames. V1 stops on guest stops; V2 continues deterministic device time.
- Offline transport bounds pending work and settles timeout, clone, fatal/decode
  and page-lifecycle failures. No network dependency or host synthesizer is added.
- Buffered native stdin preserves bounded framing, oversized-line draining,
  multi-message buffering, CRLF and final unterminated EOF requests. Complete
  two-byte disassembly remains visible at the end of the address space.
- Validation checkpoints are atomic and fail closed on timeouts, launch errors
  and changed source. Five deliberately simulated runner paths verify reporting;
  a real concurrent-edit attempt was also rejected before the final stable run.
- CI exercises real native/offline Chromium and actual cross-OS artifact transfer.
  All four major Actions upgrades are integrated and pinned by immutable SHA.
  PR commits run one matrix; main pushes and manual runs retain complete gates.

## Measured transport change

Nine alternating same-host samples restored the same exact V2 snapshot with a
135,387-byte pre-encoded request. Full native response parsing is included.

| Round trip | Before median | After median |
|---|---:|---:|
|Snapshot restore|38.433 ms|2.198 ms|
|Small observation control|0.457 ms|0.443 ms|

Canonical snapshots/states match before/after in every trial. This measures
transport and host serialization under concurrent host load, not a guest CPU
speedup, browser-wide latency promise or physical-device guarantee. Exact samples,
binary/ROM hashes and workload limits are in [transport-benchmark.json](transport-benchmark.json).

## Completed verification

The unchanged-runtime-source local checkpoint passes all 45 Debug/ReleaseSafe, native,
original compatibility, compiler/project/app, V2/vector, Workbench, portable,
cross-target and extracted/reproducible SDK gates. It includes 134 native tests
per build mode, nine real native/HTTP Workbench cases, eleven shipped-frontend
event groups against the real Wasm host, exact exported Worker transport and
five validation-driver reporting cases. [validation.json](validation.json)
records source hashes, commands, outputs, exit codes and durations.
It binds local runtime commit `c2cda05` (published as `3f737aa`). Subsequent changes
add only CI trigger consolidation and the optional long-session test; the complete
published candidate `b3fd546` passes all 17 substantive CI jobs, with release
publication deliberately skipped. [ci-source.json](ci-source.json) binds that
head and tree. Its tested synthetic merge `c948794` has the identical source tree.

The new compiler campaigns evaluate 100,000 V1 and 50,000 V2 generated cases in
both codegen modes against the separate AST evaluator: 300,000 actual ROM
executions and 1,004,631,296 retired instructions. The campaigns cover calls,
global effects, signed arithmetic, short circuiting, shifts, arrays and loops.
The earlier exploratory million-case budget was interrupted and is not counted
as a completed campaign. Only the completed bounded reports are included:
[V1](compiler-v1.json) and [V2](compiler-v2.json).

The native suite adds 2,000 seeded stateful debugger action sequences across both
profiles, comparing full/delta representations, canonical reverse and exact
re-execution. Coverage-guided fuzzing completes 252,378 runs with the recorded
new seed. Its 8.79% is feedback coverage of the composite fuzz target, not whole-
project source coverage. [Execution](fuzz-execution.json) and [raw result](fuzz.txt)
preserve the distinction. Core source did not change during that campaign.

Real Chromium executes the native service and self-contained offline local file.
Checks include exact canvas pixels, overlay geometry/scrolling, desktop/mobile
layout, real Blob Worker/CSP operation, startup/build/import/recovery, source and
snapshot/WAV downloads, actual AudioContext activation and no offline HTTP traffic.
The [checkpoint report](browser-checkpoint.json) records both modes with no page
errors or CSP violations. Final-head CI separately reruns the current sources.
The DOM-double suite is explicitly not substituted for browser rendering.

Actual Linux, Windows and macOS SDK archives are downloaded and checked without
executing foreign-OS binaries: outer SHA256, every declared member, internal
SHA256SUMS and one source revision across all three. [Downloaded checkpoint](artifact-review.json)
records this local review. Ordinary CI additionally uses the upgraded upload and
download Actions together, including the real release-style pattern/merge path.
[artifact-transfer.json](artifact-transfer.json) records the actual successful
upgraded-Action transfer and all three clean SDKs from the identical CI merge.

A separate long-lived native process per profile runs 65,552 frames, checks the
independent expected 16-bit counter wrap, reverses 32 frames across that boundary
and re-executes to identical canonical snapshots. V1 completes 1,311,040,000
retired instructions; V2 completes 1,311,040,000 device slots. Native peak RSS
is 8,192,000 bytes before/after in each process; Wasm stays at 151 pages for V1
and 153 for V2. The entire run passes in 408.253 seconds. [frame-wrap.json](frame-wrap.json)
records the final frozen native/Wasm binary identities and exact state hashes.
The ordinary CI job uses a shorter 128-frame smoke budget; it does not pretend
that short job establishes wrap coverage.

## Fixed-duration session tests

Both fixed-duration native/Wasm sessions complete successfully before integration.
Each seed drives all cartridges, fresh generated compilations, frames, input,
debugging, snapshots, valid/corrupt restores and malformed protocol messages.

| Frozen candidate | Actual seconds | Cycles | Paired requests | Generated compilations |
|---|---:|---:|---:|---:|
|Pre-buffering transport|4,500.230|9,010|441,490|1,287|
|Buffered transport|3,600.088|40,921|2,005,129|5,845|

Together they check 2,446,619 native/Wasm request pairs and 7,132 fresh generated
compilation cycles. Both retain a 44,302,336-byte Wasm linear-memory high-water
mark (676 pages); no mismatch or growth beyond the warm plateau is observed.
The differing seeds/load mean their throughput is not a controlled speed comparison;
use the alternating transport benchmark above for that measurement.

[Pre-buffering session](session-soak.json) and [buffered session](buffered-session-soak.json)
retain the actual seeds, counts, commands and frozen binary identities. Those
identities are deliberately not replaced by later rebuild hashes. The final
rebuilt native/Wasm pair is separately covered by the full frame-wrap run and CI.
Parallel builds therefore do not silently change an already running experiment.

These sessions test parity between two hosts sharing the core, not an independent
ISA oracle. The independent compiler evaluator and contract vectors cover their
own separate boundaries. Reports retain counts, seeds, command summaries, binary
hashes and the actual Wasm linear-memory high-water mark.

## Integration and limits

The reviewed set is PRs 1–9: four action upgrades, the V2/compiler/Workbench/Wasm
stack and this quality follow-up. Integration is authorized only after at least
two hours of engineering/testing and the final PR review. Normal merge commits retain the original dependency/feature commits as
ancestors, making fully integrated branches safe to remove. The final GitHub
conversation records actual merge results and main verification.

Local Chromium startup is blocked by the managed execution environment's Unix
socket policy; no alternate flags/executable were used to evade it. Supported
CI supplies the real browser evidence and screenshot artifacts. AudioContext,
PCM and WAV checks do not establish a human listening pass or every physical
sound device. Chromium checks do not establish Firefox/WebKit coverage. This
remains a development milestone, without a stable signed/notarized release.

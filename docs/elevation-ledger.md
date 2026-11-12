# Engineering elevation ledger

Baseline: d392d11 (V1), clean worktree. Zig 0.17.1 verified against pinned SHA256.
Baseline native build, automated tests and black-box acceptance passed.

## Phase 1 — host/target separation
Changed build.zig, pinned toolchain installer/metadata, cross-build regression,
and native Debug/ReleaseSafe Linux/Windows/macOS CI matrix.
Confirmed defect: asset generation was attached to the target n16asm executable.
The build now runs n16asm-build-host compiled for b.graph.host; all distributable
executables still use the selected target. Tests explicitly execute on the host;
native OS CI verifies distributables on their own platforms.

Local evidence: `python3 scripts/cross_acceptance.py` passed native Linux,
x86_64-windows, aarch64-macos and x86_64-macos ReleaseSafe builds. All four ROMs
were byte-identical across configurations. `zig build test` and
`python3 scripts/acceptance.py` passed. No SDL dependency in these builds.
Native Windows/macOS execution is **pending CI**, so phase 1 is not yet closed.
No ISA, ROM or state JSON changes. Remaining elevation phases are pending.

## Phase 2 — CPU/memory review and differential execution
Fixed a confirmed host panic when a public CPU state had an impossible stack
depth: validation now bounds depth before subtraction. Centralized stack top,
capacity and frame budget in ISA constants; removed duplicate immediate fetch.
Branch-overflow diagnostics retain the calculated address. Valid V1 execution,
ROMs and State JSON V1 semantics remain unchanged.

`zig build test`, `zig build`, and Python black-box acceptance passed. Added
stateful independent-model comparisons over 32 seeds × 300 mixed instructions,
checking every register, flags, PC, retirement, RAM and active stack after each
instruction. Existing exhaustive encodings/ALU/condition tests remain enabled.
New regressions cover invalid host stack state and guest self-modifying RAM code.
No golden image was changed. Other public CPU/bus fields remain host APIs with
valid-state preconditions; snapshot input will be validated before committing.

### Native CI follow-up
First native Windows format checks exposed Git's automatic CRLF conversion of
all Zig sources. Added .gitattributes enforcing LF source checkouts (binary PNG/
ROM exceptions). macOS 14 jobs were cancelled before execution; matrix moved to
macOS 15. Linux native Debug/ReleaseSafe and SDL jobs passed. Native Windows/macOS
remain pending the corrected matrix. Formatting assertions are not weakened.

## Phase 3 — source-aware toolchain
Implemented true token spans, stable diagnostic codes/explanations, entry-symbol
location retention, distinct undefined/cyclic constant rejection, byte listings,
JSON diagnostic schema 1, and explicit checksum-bound source/symbol JSON schema 2.
Legacy .sym files still load; --symbols output remains unchanged. Changed asm/
diagnostic/assembler, CLI assembler/debugger, debug/symbols, acceptance and docs.

`zig build test`, `zig build`, `python3 scripts/acceptance.py` passed. Regressions
assert missing entry at line 1 column 10, R8 at its exact column, overflowing
expressions, listing bytes/source, source-map ROM mismatch and legacy loading.
Exhaustive legal instruction round trips and all four golden ROMs still pass.
No ISA, ROM or State JSON V1 format changes.

### Phase 1 native gate — closed
GitHub run 43137507584 passed all native Linux/Windows/macOS 15 Debug and
ReleaseSafe execution/acceptance jobs, cross-build ROM identity and Linux SDL2.
Run 43137203853 also passed. These are native execution results, not just compiles.

## Phase 4 — debugger, trace, snapshots and undo
Added core/snapshot.zig, debug/history.zig and explicit ROM payload length state.
Extended debugger/CLI with frames, input, device peeks, source spans, 128-entry
trace, optional 32-state undo, portable save/restore and richer fault context.
Validated snapshot fields before atomic restore. Hardened the retirement limit
and invalid host reset entry so deserialized/public state cannot panic the host.
State JSON V1, ISA V1 and N16R are unchanged; N16S is independently versioned.

`zig build test`, `zig build`, `python3 scripts/acceptance.py` passed. Tests prove
snapshot byte-identical roundtrip, deterministic continuation, malformed-state
atomicity, maximum counter safety, input/frame operation, trace writes, reverse,
read-clear preservation, source-map association and CLI save/load. All old golden
images pass. No known open core correctness failure; GUI/platform hardening,
fuzzing, performance and release work follow.

## Phase 5 — systematic malformed inputs and guided fuzzing
Added dedicated bounded fuzz targets, a deterministic seven-family smoke suite,
allocation-failure regression, API input limits and push/scheduled fuzz/coverage
workflows. `zig build test`, build and full CLI acceptance passed. Actual
`zig build test -Doptimize=ReleaseSafe --fuzz=1K --test-timeout 5m` passed: 1179
runs / 174 unique / 841 of 15441 feedback PCs. Default Debug backend's zero-PC
coverage failure is documented; the successful LLVM mode is explicit in CI.
No failures were suppressed. kcov publication remains pending CI execution.

### Coverage dependency correction
The guided fuzz CI job passed. Source coverage failed because kcov is absent from
the Ubuntu runner's package repositories. CI now builds kcov v43 at exact upstream
commit a39874f938ce13f7a65f253120d1ec946b349ffe; coverage is still pending execution.

## Phase 6 — SDL2 ABI and graphical acceptance
Replaced handwritten SDL structs/constants with a header-compiled C adapter and
checked project-owned input ABI. Added resizable/high-DPI integer scaling,
performance-counter pacing, event-based held keys/focus release, cleanup/error
paths and native graphical acceptance matrix. Changed build, frontend C/Zig,
gui-test executable, CI and graphics documentation.

Local `zig build -Dgui=true --search-prefix ../sdl-sdk/prefix` and dummy-driver
`zig build gui-test` passed against official SDL2 2.32.4 headers/runtime. The test
boots three guests, measures all renderer pixels, verifies resized letterboxing,
all keys, releases, controls, quit/focus and guest paint. A viewport-clipped
readback defect was caught and fixed without weakening the pixel comparison.
The expanded guest-paint assertion initially used an even-X expected nibble
after moving to odd X; it was corrected to F0, preserving the neighbour. The
phase-6 ledger was initially written before that expanded gate finished; this
correction is recorded explicitly. Native
Windows/macOS graphical acceptance is pending the new CI jobs; not yet claimed.
The corrected expanded local phase-6 gate has now completed successfully:
dummy SDL ABI/events/controls/scaling/readback, core tests, default build and
complete black-box acceptance all returned exit 0. Native GUI CI remains pending.

### Native graphical gate — closed
GitHub CI run 43140210006 passed graphical acceptance natively on Linux,
Windows 2022 and macOS 15, plus all native Debug/ReleaseSafe and cross-build jobs.
Fuzzing passed separately. kcov's build needed its v43 tag for git-describe;
the shallow pinned checkout now supplies that local tag. Source coverage remains
pending a successful measurement; it has not been represented as passing.

## Phase 7 — measured performance baseline
Added native benchmark tool/build targets, isolated peak-RSS collector and per-
commit CI artifacts. Measured CPU/frames, initialization/reset, bus, RGB rendering,
ROM validation/load and assembly; hardware/compiler/mode and executable hashes
are recorded. Exact commands/results are in performance.md. Local benchmark,
core tests, default build and CLI acceptance all passed. No speculative engine
optimization or golden change. Linux profile measured 51.40 ns/instruction,
1.019 ms/frame and 13,312 KiB benchmark process peak RSS. Host perf is unavailable;
component timing is reported accurately rather than claimed as sampling analysis.

### Phase 5 source coverage — closed
GitHub Fuzz and coverage run 43140891457 passed both guided fuzz and kcov source
coverage jobs and published the source-coverage artifact. The tooling failures
were fixed; no failed step was masked or made optional.

## Phase 8 — verification-gated release engineering (publication pending)
Added pinned action SHAs, read-only/default workflow policy checks, dependency
updates, native package extraction/acceptance, reproducible archive timestamps/
permissions, per-file and archive SHA256, source/build-info manifests, baseline-
CPU stripped binaries, --version/--build-info and a fully gated prerelease job.
Added installation, contribution/security/compatibility, changelog and release
process documents. Repository administration/rulesets are intentionally unchanged.

Local `zig build fmt`, tests (60/60), ReleaseSafe baseline-CPU stripped build,
black-box acceptance, package build/extraction and security policy all passed.
Two local package runs produced identical ZIP SHA256; extracted binaries really
assembled and booted all four sources and ran the debugger without Zig or SDL.
Native package CI and actual release publication remain open until those run.
The distribution is explicitly 0.2.0-rc.1; no stable-release label is claimed.

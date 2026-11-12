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

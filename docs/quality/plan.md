# Workbench reliability and integration plan

Work started on 2026-11-15 at approximately 09:07 UTC. The requested minimum
engineering period is two hours. This work builds on PR #8, with #5–#7 beneath
it, and preserves all V1/V2 hardware, ROM, snapshot and compiler contracts.

## Audit and selected scope

The existing native core already has extensive conformance, differential,
snapshot, fuzz and cross-platform coverage. The weakest verified boundary is
the user-facing Workbench: previous checks execute the VM and Worker but do
not exercise the actual application event handlers. The following concrete
findings drive this milestone.

| Finding | Change | Evidence |
|---|---|---|
|Syntax overlay inherits the gutter's width/alignment/background|Isolate gutter and code styles; keep text selectable and scroll-aligned|CSS checks and real-browser layout checks in CI|
|Guest and host controller masks can diverge after rewind/reset/load/replay|Track keyboard/pointer owners independently; synchronize actual VM input; release on focus loss|Actual frontend handler tests including overlapping controls and delayed responses|
|Source line marks and labels survive machine/editor changes inconsistently|Track the successfully compiled source and target; update location presentation on edits|Build/edit/load/failure race regressions|
|Run/Pause status can remain stale or render READY after a frame stop|Render transport state immediately and distinguish debugger stops|Actual frontend state/transport tests|
|Offline replay accepts a different grammar and reports requested rather than executed frames|Use explicit matching bounded schedule validation and actual progress|Native/offline invalid schedule and halted replay parity|
|Worker startup, transport and page lifecycle leave unbounded or unresolved requests|Bound outstanding work, settle timeouts/clone failures/message errors/disposal|Exact exported Worker transport tests|
|Unsubmitted source is lost on refresh; browser storage denial can prevent boot|Bounded best-effort draft persistence with clear status and explicit import/export|Storage-denial, draft reload, file validation tests|
|Only bundled/compiled cartridges are loadable through the UI|Bounded V1/V2 cartridge import with candidate-before-replace validation|Native/offline/frontend/browser import and corrupt-file retention checks|
|Resume clears guest BRK before history captures the prior state|Group resume and its first transition in the shared debugger|Both profiles and history modes, zero-step/continue/next, embedded groups and 2,000 seeded sequences|
|Native stdin is read with one OS call for every byte|Streaming 8 KiB input buffers without changing framing budgets|Buffer boundaries, EOF/oversize recovery, native/Wasm session soak and alternating restore round-trip samples|
|Validation timeouts/launch errors and concurrent edits can leave ambiguous evidence|Atomic report checkpoints, explicit failures and final source digests|Five simulated failure/success paths plus the actual source-change rejection|
|Browser execution has no continuous gate|Optional Playwright suite for native and offline Workbench, separate CI job|Actual Chromium execution in CI; local restrictions recorded honestly|
|README/manual contradict implemented V2/history/app behavior|Reconcile current usage and limits|Documentation review against source|

## Execution order

1. Establish ReleaseSafe native/Wasm baseline and inspect all eight PR diffs,
   review threads and their exact-head checks.
2. Implement the bounded session/UI fixes and regressions. Keep runtime free
   of third-party dependencies; browser test tooling is development-only.
3. Run Debug/ReleaseSafe, original compatibility, native/offline/Wasm, project,
   package/reproducibility, source formatting and security gates. Add browser CI
   and inspect its real results rather than treating a DOM shim as a browser.
4. Publish a focused quality PR. At the end of the requested period, review and
   merge all ready PRs in dependency order, retargeting stacked PRs to main.
   Recheck the integrated main tree and record merge/check evidence. Preserve
   any branch with unmerged unique work; do not silently bypass failing checks.

## Limits

Local Chromium startup is currently denied by the execution environment's Unix
socket policy. No flags or alternate executable will be used to circumvent it.
The repository browser suite must run in its supported CI environment. Browser
audio checks establish Web Audio delivery/PCM, not a human listening test or
universal device/OS latency guarantee. This is a development-quality milestone,
not a signed stable release or a change to fictional hardware capabilities.

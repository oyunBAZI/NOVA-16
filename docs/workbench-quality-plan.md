# Workbench quality milestone — 2026-11-15

## Audit and decision

Source inspected: `11b13abafa086990bd0dbf2e8f5b0f06ac474576`, the compact-linking
checkpoint stacked on V2 PR #5. Both #5 and #6 are still open. A fresh native
Debug run on the unchanged checkpoint passes 119 tests. The existing core,
compiler, contracts, replay fixtures and CLI are substantial working systems.
Rewriting them would add compatibility risk without resolving the biggest
usability gap: there is no integrated develop/run/inspect/rewind workflow.

The chosen deliverable is a complete optional local Workbench slice. The
hardware profiles, ROM/snapshot encodings, ABI, original state JSON and golden
fixtures remain fixed. This is not the whole ten-phase historical mission.

## Plan and acceptance criteria

| Step | Implementation | Required proof |
|---|---|---|
| 1 | Bounded versioned native VM bridge, owning one live machine | Rejected and oversized requests recover; observation never acknowledges MMIO; request allocations are freed |
| 2 | Reuse the instruction debugger and canonical V2 scheduler | Same registers, pixels and integer PCM as native headless execution; precise break/watch stops |
| 3 | Make frame rewind useful at bounded cost | One full-state copy per frame action, exact reverse/re-execution, original instruction history behavior preserved |
| 4 | Integrate single-file typed editing/building and real VM inspection | Failed builds retain the running VM; successful builds use real compiler maps and size reports; candidate VM validates before replacement |
| 5 | Add browser presentation, snapshots, controller input and replay | Local HTTP auth/origin/host/size checks, exact snapshot restore, deterministic native-scheduler replay |
| 6 | Ship the whole workflow | Include native bridge, frontend and acceptance in SDK; extracted SDK acceptance; Debug/ReleaseSafe regression gates and CI matrix |

## Architecture

`src/workbench/session.zig` is a headless host model. It uses `Machine`,
`Debugger`, checked snapshots, nonacknowledging bus inspection and the existing
renderer data. It does not own filesystem access, a browser or a synthesizer.
`n16bridge` wraps that model in JSON lines over stdin/stdout, without protocol
file paths. It owns per-request allocations and a fixed 32-entry exact history.

`scripts/workbench.py` provides one serialized local session, fixed demo IDs,
isolated compiler staging and static assets. The browser only presents native
observations and queues real guest PCM. The complete frontend uses system fonts,
plain HTML/CSS/JavaScript and Python's standard library; no build-time package
execution or downloaded runtime dependency was introduced.

## Scope and deferred work

This milestone provides single-file N16C editing, source locations and source
breakpoints through the console, instruction/source/frame stepping, live
registers/disassembly/memory/palette/pixel/voice/IRQ inspection, exact rewind,
snapshot download/restore, source/ROM export, guest-controller input, native
frame replay, and bounded host PCM playback/WAV export.

It does not add an assembly/project filesystem editor, a language server,
unbounded/delta history, new hardware profiles, Tracker/Starfall, or public
hosting. Those need their own concrete acceptance criteria. The browser view is
an optional host frontend, not a replacement for the native SDL application.

## Evidence

Executed commands and results are recorded in `docs/reliability/workbench-local.json`.
Native browser visual verification is a separate gate: the managed cloud browser
could not reach this execution container's loopback server; an attempted local
Chromium test launch was also prevented by the execution environment's socket
restriction. HTTP/native tests do not constitute a browser layout/sound-device
check. Do not promote a stable GUI release based on those checks alone.

## Same-host performance observation

Seven ReleaseSafe fresh-process measurements of NOVA Sound (one V2 frame,
32-entry history) measured median 66.85 ms for the instruction-undo CLI and
3.32 ms for the frame-action-undo bridge including JSON output. Raw samples
and comparison limits are in `docs/benchmarks/workbench-linux.json`. This is
the intended history-granularity tradeoff, not a claim that the CPU is 20× faster.

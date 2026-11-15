# Platform evolution milestone — 2026-11-15

The user requested a substantial improvement and at least ninety minutes of
continued engineering. Work began at 04:47:21 UTC. This milestone builds on the
Workbench tree from PR #7 and keeps the V1/V2 ISA, hardware, ROM envelopes,
portable snapshots, source-map contracts and original golden fixtures fixed.

## Audit findings and chosen work

| Finding | Implementation | Required evidence |
|---|---|---|
|Typed programs repeatedly spilled temporaries and materialized conditions|Size code generation with an explicit baseline mode|Independent AST oracle and real CPU comparisons, signed/wrap/evaluation-order cases, exhaustive 16-bit inputs|
|Generic rectangles called a pixel routine for every pixel|Packed VRAM spans and unrolled word clear|Independent pixel oracle over odd/even/clipped boundaries, ABI sentinels and exact instruction counts|
|Reverse history held only 32 whole machines|Bounded state-plus-write delta ring with frame deduplication|Compare against complete-state undo, eviction/wrap/reverse/branch/IRQ/partial-PCM tests, deeper real-app replay|
|Typed applications could not explicitly select V2|Compiler/project/Workbench target selection|ROM2 header/profile activation, V1 denies, identical native/Wasm compiler bytes|
|V2 demos did not form interactive end-user workloads|NOVA Tracker and Starfall|Real guest controls, musical/device state, win/loss/pause/restart, native/bridge PCM/pixel/RAM parity|
|The Workbench required native tools and a Python service|Import-free Wasm VM/compiler and offline Worker export|Eleven-ROM native parity, snapshots/maps, repeated replacement/memory bounds and offline host acceptance|
|macOS exposed a transport race in an HTTP test|Reject oversized requests at headers in the test|Preserve the actual boundary assertion and rerun native CI|
|Validation was split across many commands|One reproducible validation driver and expanded CI/package gates|Recorded commands/results, cross-target ROM identity, extracted SDK and exact-byte reproducibility|

## Scope and review limits

This is an implemented development milestone, not a claim that every phase of
the historical mission is finished. The optimizer deliberately keeps mutable
reads, evaluation order, diagnostics, runtime bounds checks and ABI layout. It
has no SSA, register allocator, arbitrary dead-store elimination or general
assembler optimizer. Unoptimized code generation is retained as an additional
comparison path, not as an independent semantic oracle.

Delta history is bounded by both entry count and write-journal capacity. It can
evict old complete actions before the requested entry count is reached. The
complete-state mode remains available. Embedders must route guest transitions
through the recorder and clear history on out-of-band reset/restore/ROM changes.
No filesystem/network peripheral or new hardware profile was introduced.

The offline export is a real Wasm runtime, compiler and Worker model, using the
shared Workbench UI. Node execution verifies behavior and script structure. The
managed browser's loopback/file-navigation restrictions prevented a rendered
browser/audio-device check. Those checks remain explicit release gates; neither
Node parity nor generated framebuffer previews establish a browser visual pass.

Source, measured results and executed checks are recorded with this milestone's
engineering evidence. Main merges, releases and OS signing are separate from
publishing a reviewable feature branch.

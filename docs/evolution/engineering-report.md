# Platform evolution engineering report

This milestone addresses generated-code cost, guest rendering cost, useful
reverse depth and portable access to the complete VM/compiler workflow. It
adds two real V2 application workloads while retaining the original hardware
and binary contracts. The scoped decisions are in [plan](plan.md).

## Measured outcomes

| Workload | Baseline | New result |
|---|---:|---:|
|Crates ROM payload|7,100 bytes|4,240 bytes (40.28% smaller)|
|Pixel Studio ROM payload|4,222 bytes|3,190 bytes (24.44% smaller)|
|NOVA Tracker|Baseline compiler rejects ROM overflow|5,666-byte V2 typed program|
|Starfall|Baseline compiler rejects ROM overflow|7,686-byte V2 typed program|
|Full-screen rectangle, guest instructions|498,280|38,170 (13.05× fewer)|
|Clear, guest instructions|12,306|5,394 (2.28× fewer)|
|Odd, clipped rectangle, guest instructions|310,907|24,629 (12.62× fewer)|

Graphics counts include the identical caller fixture and execute both library
versions on the same unchanged CPU implementation. Their final framebuffer
bytes match. Rectangle semantics also have 160 independently constructed pixel
oracle cases with clipping, initial random neighbour nibbles and ABI sentinels.
The five original V1 ROM identities and all existing application/framebuffer
fixtures are separately checked without updating their golden values.

Seven same-host component samples measured median 9,101.77 ns per complete-state
recorded instruction versus 178.46 ns for a 32-entry delta ring and 414.62 ns for
a 2,048-entry ring. Delta reverse measured 84.26 ns per action on the benchmark's
simple CPU loop. These are measured host/history costs for that workload, not a
CPU hardware speedup or a promise for write-heavy grouped frames. A separate
write-journal budget governs actual retention. The old capture-only experiment
remains labelled a lower bound, not a complete implementation.

Raw samples, source hashes and exact fixture counts are in `components.json`
and `workloads.json`. Compile wall-clock samples were taken while other local
checks could use the host. They contain visible scheduling outliers and are not
used to claim a universal compiler speed improvement. ROM sizes and guest
instruction counts are deterministic and are the primary results.

## Correctness and failure boundaries

The V1 grammar campaign executed 100,000 generated programs in both codegen modes
(200,000 real ROM runs). A deeper V2 campaign executed another 50,000 programs in
both modes (100,000 ROM runs). Both compare against the separate wide-integer
AST oracle, including global side effects, calls, arrays, loops, signed division,
short circuiting and evaluation order. Together they retired more than 722
million instructions. The native suite additionally checks every one of 65,536
input words in both codegen modes for the targeted strength/shift expressions.
The oracle is a maintainer test tool and never executes shipped applications.

The delta ring is tested against whole-machine undo through wrap, eviction,
branching and frame groups. V1 read-clear/palette/stack/trap cases and V2 IRQ,
partial-PCM and frame-boundary cases run in both representations. Journal-pressure,
oversized-group and allocation-failure tests retain only complete actions.
An actual Tracker session reverses sixty frames and re-executes to identical
canonical snapshot bytes, beyond the old 32-entry limit.

The new application suite pins ten scenes and checks guest RAM, edits, win/loss,
pause/resume/restart, native/bridge CPU state and exact final-frame PCM. Native
project tests explicitly budget the requested frames so late input events cannot
be skipped by an unrelated default instruction cap.

The Wasm module is import-free and uses the same core/compiler and protocol
serializer as native tools. Node executes all eleven ROMs and compares native
state, pixels, PCM, snapshots, rewind/rejection, compiler ROM bytes, map ownership,
independent instances and repeated replacement/memory bounds. Review caught a
legacy-symbol lifetime bug; the map now owns its text and tests reuse the shared
input buffer before querying symbols again. A separate offline-export check
validates embedded scripts/assets and executes build/replay/revision/failure
handling through the same model used by its Worker. An additional test executes
the export's exact launcher and generated Worker source in a real Node thread,
including concurrent-message revision rejection and typed V2 execution. It does
not pretend that Node's Worker plumbing implements browser URL/CSP policy.

## Verification and release limits

The validation driver records each executed command, exit status, duration and
output. Debug and ReleaseSafe native, original compatibility, compiler/project,
application, V2 vectors/audio/IRQ/snapshot, Workbench/HTTP, security and project
stress gates remain separate from portable and package gates. Cross-target builds
compare all eleven ROM assets for native, Windows x86_64, macOS arm64 and macOS
x86_64; cross compilation does not claim native OS execution. GitHub's native
matrix supplies its own evidence after publication.

The earlier local fuzz campaign completed 101,658 coverage-guided runs. Its
reported 7.72% is the fuzzer's feedback coverage for that composite target, not
whole-project test coverage. The protocol family was subsequently added and
receives an additional run recorded separately. The final SDK checks validate
all checksums, extracted workflows, applications, Wasm/offline model where Node
is present, and exact-byte reproducibility.

Rendered browser and real audio-device testing remain open. The managed browser
could not connect to execution-container loopback and its URL policy rejected
local-file navigation; no attempt bypassed that policy. Native framebuffer
previews and Node tests do not establish DOM layout, Blob Worker/CSP behavior
or sound-device playback in a browser. This is a reviewable development milestone,
not a stable GUI or signed/notarized OS release.


## Final boundary review

A final review found that a large valid symbol listing could exceed the Python
bridge reader's framing limit. Shared serialization now bounds the complete
response before publication and separately bounds command text. Overflow returns
`OutputLimit` while preserving the live machine. Regressions cover 3,000 long
symbols and a 600,000-byte source path in both native and Wasm, including exact
snapshot retention and a subsequent successful step. This is a protocol/host fix;
no CPU, device or snapshot format changed.

The expanded composite fuzz campaign completed 1,003,883 runs with 3,528 unique
feedback runs and 9.37% fuzzer-target coverage. It includes the new shared-protocol
family and predates the final serialization-budget patch; that patch has its own
native/Wasm overflow recovery regressions and follow-up checks. These percentages
are not whole-project code coverage. Raw results and command/seed/duration are
recorded in `protocol-expanded-fuzz-*` alongside the earlier campaign.

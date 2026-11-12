# Maintenance and next milestones

## Implemented for 0.3.0-rc.1
V1 CPU/devices/ROM/snapshot/state compatibility; checked embedding operations;
indexed bounded assembly, rich/multi-error diagnostics and staged output;
root-bounded multi-file sources with reproducible maps; source/symbol debugging;
a complete guest developer workflow and CPU-native Breakout; allocation-failure,
differential, replay/fuzz/coverage checks; native package/GUI gates and measured
component workloads. See v0.3-ledger.md for actual local/native/release status.
A feature listing does not substitute for its pending platform/publication gate.

## After release-candidate review
1. Accumulate scheduled 100K fuzz evidence and preserve failures as regressions.
2. Extract reusable graphics/input/number/font routines from Breakout with a
   documented caller/callee register contract and independent guest tests.
3. Build a small V1-only compiler experiment with bounded parsing, exact wrapping
   arithmetic, source maps and reference-interpreter comparisons.
4. Expand native OS/CPU runners where available; macOS x86_64 remains cross-only.
5. Evaluate source-text/editor integration and explicit object/linker formats only
   when current includes become insufficient; preserve old formats/readers.
6. Review optional installers and OS signing/notarization separately. Workflow
   provenance is distinct from executable signing. No branch rules are bypassed.
7. Profile representative guest software on equivalent hardware before optimizing
   dispatch or changing resource limits. Do not inflate code to meet a line count.

## V2 requires separate design approval
The concrete proposal is [V2 architecture revision 1](v2-architecture.md): explicit
profile/format activation, deterministic audio, IRQ entry/return, compatibility
vectors and phased acceptance. An isolated arithmetic experiment is available
through `zig build v2-model-test`; it adds no guest hardware or sound output.
Publish complete V2 snapshot/trap vectors before implementing architectural
extensions. Networking/filesystem peripherals remain outside this milestone.

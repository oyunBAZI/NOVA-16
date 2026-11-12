# Maintenance and next milestones

## Delivered V1 Developer Platform

v0.4 adds hardened persistent state/embedding, executable ABI1, guest arithmetic/
memory/graphics/input/runtime library, bounded typed n16c compiler, independent
AST/CPU differential checks, source variables and maps, reproducible local
projects, exact event undo, Crates and Pixel Studio. It retains the original
CPU/devices/ROM/snapshot/state formats and all five original ROM byte identities.
See v0.4-ledger.md and GitHub CI/Releases for local/native/publication evidence.
The original v0.3 work and evidence remain in v0.3-ledger.md.

## After release-candidate review

1. Accumulate scheduled100K fuzz evidence; minimize failures as regressions.
2. Extend language workloads and independent oracle seeds before optimization.
   Evaluate unused-library elimination/compact codegen against current8KiB limits;
   do not silently grow ROM or change ABI/ISA to accommodate applications.
3. Expand native OS/CPU runners where available; macOS x86_64 remains cross-only.
4. Evaluate editor/object/linker integration only when existing source projects
   require it; version relocations/types/layout before introducing object files.
5. Review installers and OS signing/notarization separately. Workflow provenance
   does not provide executable signing; repository protection is not bypassed.
6. Profile representative guest workloads on comparable hardware. Deeper reverse
   history requires measured exact delta/checkpoint tests, not capture-only timing.

## V2 requires separate architectural approval

Review [V2 revision2](v2-architecture.md) and its normative
[binary/transition contract](v2-binary-contract.md), with independent byte/PCM/
timer/IRQ vectors. Approve explicit profile activation, idle/fault clocks, MMIO
atomicity and interrupt frame semantics before implementation. Then implement
profile dispatch, headless deterministic audio/WAV, timer/IRQ/IRET and snapshots/
reverse; prove V1 isolation at every gate; add optional host playback last.
The isolated arithmetic experiment is not a sound device. Networking/filesystem
peripherals remain outside this milestone. The completed V1 platform does not
implicitly authorize or claim V2 hardware.

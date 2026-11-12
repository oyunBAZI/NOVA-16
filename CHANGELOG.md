# Changelog

## 0.3.0-rc.1 — developer platform
- Checked embedding transitions and atomic host memory patches.
- Indexed, iterative constant resolution with bounded parsing and rich/multi-error diagnostics.
- Local multi-file inclusion, project boundaries and reproducible source maps.
- Source breakpoints, statement stepping, symbols and richer trap reports.
- Versioned ROM inspection, guest tests and reproducible guest-source packages.
- Complete CPU-native Breakout game with real win/loss/restart and replay hashes.
- Allocation-failure ownership fixes, source-alias protection and extended fuzzing.
- Native project/package/GUI verification and expanded representative benchmarks.
- Gated release provenance generation/verification; OS binaries remain unsigned.

ISA V1, N16R V1, N16S V1 and State JSON V1 are unchanged. Existing diagnostic
JSON schema 1 and symbol-map schema 2 remain supported. New inspection, guest
test and guest-package formats use schema 1; multi-error diagnostics opt into
schema 2. Architectural sound/interrupt extensions remain a separate V2 proposal.

## 0.2.0-rc.1 — engineering elevation
- Host-native asset assembler and tested Windows/macOS cross-build graph.
- Native Linux/Windows/macOS Debug/ReleaseSafe and graphical verification.
- Stateful differential execution, bounded fuzzing and source coverage.
- Real assembler spans, IDE JSON diagnostics, listings and checked source maps.
- Frame/input debugger, bounded traces/history, N16S snapshots and reverse steps.
- SDL2 header adapter, high-DPI integer scaling and renderer/event acceptance.
- Measured component benchmarks, release packaging/checksums and security policy.

ISA V1, N16R ROMs and State JSON V1 remain compatible. N16S V1 and source-map
schema 2 are new explicit formats. Legacy symbol maps remain supported.

## 0.1.0
Initial V1 CPU, memory/devices, assembler, debugger, optional SDL2 and four ROMs.

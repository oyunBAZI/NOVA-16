# Development and reproduction

Pin Zig 0.17.1. No package fetch occurs during the Zig build. Official archive
URLs/checksums for CI platforms are committed in scripts/toolchains.json;
scripts/setup_zig.py verifies the archive before extraction.

```
zig build fmt
zig build
zig build test --test-timeout 2m
zig build demos
python3 scripts/acceptance.py
zig build -Doptimize=ReleaseSafe -Dstrip=true -Dcpu=baseline
python3 scripts/acceptance.py
zig build test -Doptimize=ReleaseSafe --fuzz=1K --test-timeout 5m
python3 scripts/security_check.py
```

Cross-compile distribution binaries without executing them on the host:

```
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe
zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe
python3 scripts/cross_acceptance.py
```

Host assembler always targets b.graph.host; distributable executables target the
selected platform. Native tests execute on the host. Native OS CI tests target
binaries, including package extraction, on their own OS. Platform evidence is in
platforms.md. This distinction is part of the build contract.

For SDL2, install development libraries and use `zig build -Dgui=true` and
`zig build gui-test -Dgui=true`. A prefix can supply headers/import libraries.
The C adapter is built only for graphical executables. Default builds/tests
remain SDL-free. Native event/readback tests and original desktop validation
are described in gui.md.

## Modules and ownership
`arch/isa.zig`: constants, opcode tables and strict decoding.
`core/`: CPU, bus, traps, reset/frame machine, input schedules, snapshot encoding.
`devices/`: input and deterministic RGB conversion.
`rom/format.zig`: checked N16R packing/loading.
`asm/`: lexing, parsing, spans/diagnostics, symbols, two passes and emission.
`debug/`: disassembly, checked source maps, command engine, trace/undo recorder.
`frontend/`: header-compiled SDL2 adapter and host orchestration.
`cli/`: host I/O and command policies, graphical acceptance and benchmarks.

Machine owns CPU, bus/memory/devices and loaded ROM metadata. Caller supplies
allocators for serialized outputs/toolchain results. Assembly result names/source
slices borrow the source text; keep it alive until the result is released.
Loaded JSON symbol maps own parsed data until deinit; legacy map names borrow
the map text. Debugger deinit releases optional undo storage. All format loaders
validate before committing live state.

Tests live beside their subsystem, with dedicated conformance, sequence,
integration and fuzz suites. Never change a golden hash without a reviewed guest-
visible reason. Current elevation preserved every original V1 ROM image/hash.

## Troubleshooting
- Compiler/API error: `zig version` must be 0.17.1.
- Default fuzz backend zero-PC coverage: use documented ReleaseSafe/LLVM mode.
- SDL missing: install development headers/library or supply a search prefix.
- GUI binary starts then exits: defaults are finite; increase explicit limits.
- Debugger repeats a breakpoint: step or delete before continue.
- Source/snapshot identity mismatch: use the files from the same ROM build.
- Source layout error: align instructions and resolve layout constants beforehand.
- macOS unsigned CLI restriction: build from source or follow local signing policy.

See releasing.md for archive generation, checksums, native verification and
publication gates. Repository rulesets/code signing are not silently configured.

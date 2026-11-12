# Development and release reproduction

Pin Zig 0.17.1. The build rejects other compiler release versions. The Linux
x86_64 archive SHA-256 was checked against the official download index:
`3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a`.
No package dependencies are fetched by the Zig build.

From a fresh clone:

```
zig build fmt
zig build
zig build test
zig build demos
python3 scripts/acceptance.py
zig build -Doptimize=ReleaseSafe
python3 scripts/acceptance.py
```

For SDL2 install the platform development package, then:

```
zig build -Dgui=true
zig build test -Dgui=true
SDL_VIDEODRIVER=dummy zig-out/bin/nova16 run zig-out/demos/boot_splash.n16 --gui --frames 6
```

For a visible Linux smoke test use Xvfb or the actual desktop. A dummy-driver
smoke exercises texture/event/presentation code but does not replace the recorded
real desktop keyboard/display validation. Platform evidence is in gui.md.

## Modules
`arch/isa.zig` owns instruction metadata/constants and strict decoding.
`core/` owns CPU, bus, traps, machine reset/frame execution and input schedules.
`devices/` owns input state and deterministic RGB rendering. `rom/format.zig`
validates/packs containers. `asm/` separates source lexing, parsing, operand
encoding and two-pass symbol/emission logic. `debug/` is a core debugger API
plus canonical disassembly. `cli/` owns host I/O and command-line policies.
`frontend/sdl2.zig` is the isolated C ABI adapter.

Tests live beside their subsystem, plus integration_tests.zig and
conformance_tests.zig. Golden images are generated from real assembly, never
fixtures substituted by the renderer. Avoid changing expected hashes unless
you understand the guest-visible change; explain it in the milestone ledger.

## Distribution
`zig build -Doptimize=ReleaseSafe` produces native `zig-out/bin/{nova16,n16asm,n16dbg}`
and `zig-out/demos/`. Package these with LICENSE and docs. The default headless
binaries need no SDL. A GUI build dynamically requires SDL2 on the destination.
GitHub Actions uploads the Linux headless binaries/ROMs as a workflow artifact.
No installer or code-signing claim is made. macOS/Windows builds are unverified;
cross-target demo generation currently requires a host assembler/native build.

## Troubleshooting
- Compiler/API errors: verify `zig version` is exactly 0.17.1.
- SDL2 library missing: install its development package, or supply a valid
  library search prefix. The headless build never needs SDL2.
- `GuiDisabled`: rebuild with `-Dgui=true`.
- Window disappears: default 120 presentations is about two seconds; increase
  `--frames` and, for long-running guests, `--max-instructions`.
- Guest stops without HALT: inspect paused/trapped status and instruction budget.
- Debugger repeats a breakpoint: use step or delete before continue.
- PPM unsupported by image viewer: open in GIMP/ImageMagick, or convert to PNG.
- Assembly layout error: align instruction addresses and define layout constants
  before their use; instruction/data label references may be forward.

Core invariants: never consult host time, never bypass bus validation for guest
accesses, never clear read-latched devices during debugger inspection, and never
let malformed ROM/assembly/debugger inputs panic the host.

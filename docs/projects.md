# Local project workflow (schema 1)

Python 3.10+ and a native NOVA-16 build are required. Run from the SDK root:

```
python scripts/n16.py new /path/my-app --language n16c
python scripts/n16.py build /path/my-app
python scripts/n16.py test /path/my-app
python scripts/n16.py run /path/my-app -- --headless --frames 120
python scripts/n16.py debug /path/my-app
python scripts/n16.py pack /path/my-app --out /path/my-app.zip
```

Use `--language asm` for assembly. `--bin-dir PATH` before the command chooses
installed tools. Debug launches n16dbg with the freshly compiled source map;
`break main.n16c:1`, `next`, `vars`, `trace`, `history 32`, `reverse` work normally.
The starter test boots the real CPU and checks HALT/R0=42. Edit that expectation
when changing main. No emulator source edits or network dependency resolution.

`n16-project.json` contains exactly schema_version=1, name (1–64 characters),
language (`asm`/`n16c`), entry, files and tests. `files` is an explicit unique
allowlist, at most 128 paths/1MiB total including input schedules and assembly
includes, regardless of extension. Paths are canonical relative slash paths;
symlinks, parents, absolute paths and reserved build/manifest names are rejected.
Builds see an isolated copy of only declared files. Missing/undeclared includes
therefore fail; no dependency is silently omitted from packages. The compiler
currently accepts a single typed source file; assembly supports local includes.

Tests (maximum 64) specify frames (1–10000), optional input (declared schedule),
registers (string register indices 0–7 to u16), halted (boolean) and ppm_sha256.
Traps always fail. Expectations execute in fresh VM processes and real CPU
frames. The tests use V1 JSON/PPM and the existing schedule format.

Builds publish ROM, checksum-bound source map, source digest/compiler metadata,
and (typed projects) generated assembly and memory layout under `.n16/` after
successful compilation. Each publication uses staged files; this is not a
cross-file crash transaction. `run/debug/test/pack` always rebuild and abort on
failure, so retained prior outputs cannot be executed as a successful rebuild.
Package runs all declared tests first, then stores original sources/schedules,
manifest and build outputs in a sorted ZIP with fixed timestamps/permissions and
SHA256 integrity manifest. Extract and use the same workflow to rebuild/test.
Packages are byte reproducible on the same tools; tool-version metadata can
differ across SDK versions. There are no downloaded or external dependencies.

# Reverse history decision

Measured before changing history: Linux x86_64 ReleaseSafe, Zig0.17.1, one
10000-step sample: full-state history 15.824ms; metadata-only candidate capture
lower bound 0.544ms. `zig build bench -Doptimize=ReleaseSafe -- --samples 1
--instructions 100000` reproduces this comparison on the current host. The
candidate is deliberately not a complete delta implementation: it excludes
write extraction, checkpoint restoration and exact MMIO transition handling.
These timings do not establish end-to-end delta reverse performance.

The exact full-state implementation is retained for v0.4: explicit opt-in,
32 entries maximum, 2,101,248 bytes, no history allocation while disabled.
This bounded cost is acceptable for this SDK and avoids shipping an unproved
checkpoint/delta state machine. Further history depths require a separately
measured implementation. Input changes and frame-end metadata transitions now
create undo entries, fixing previously incomplete frame-boundary reversal.
`reverse` undoes one recorded instruction or external device event. Reset/ROM
load/snapshot load clear history. Tests compare exact serialized replay across
RAM/stack/VRAM/palette/read-clear latches/traps and frame transitions. Trace
records instructions; reversing an external event clears the forward trace.

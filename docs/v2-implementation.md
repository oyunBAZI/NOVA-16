# Using NOVA-16 profile2

This development implementation follows revision2 without changing the V1 ISA,
ROM bytes, MMIO denies, snapshot bytes or State JSON1. See the implementation
ledger for completed verification; an implementation is not a published release.

## Build and run

Use exactly Zig0.17.1. The default build is headless with no dependencies.

```sh
zig build
zig-out/bin/n16asm examples/projects/nova_sound/main.asm --architecture nova16-v2 --out nova-sound.n16 --debug-symbols nova-sound.map.json
zig-out/bin/nova16 inspect nova-sound.n16 --json
zig-out/bin/nova16 run nova-sound.n16 --frames 180 --wav nova-sound.wav
zig-out/bin/nova16 run zig-out/demos/interrupt_canvas.n16 --frames 180 --wav canvas.wav --screenshot canvas.ppm
zig-out/bin/n16dbg nova-sound.n16 --symbols nova-sound.map.json
python3 scripts/n16.py test examples/projects/nova_sound
python3 scripts/n16.py test examples/projects/interrupt_canvas
```

V2 assembly requires the explicit architecture option; default assembly is V1.
Unknown architecture names, ROM versions, profiles and feature bits fail closed.
Project manifest2 requires `architecture` and supports assembly; manifest1 and
N16C keep their existing V1 behavior. Source map formats are unchanged.

NOVA Sound uses all four oscillators and an eight-note timer-driven melody.
Interrupt Canvas adds timer-drawn pixel pairs and frame-driven palette animation.
All setup, sequencing and drawing execute ordinary guest instructions. Source,
ROMs and maps are built reproducibly; native SDK packages also contain three-second
48kHz mono signed16 WAV renders. These simple chip waveforms intentionally alias.

`--wav` requires headless V2 and at most3600 requested frames (one minute).
Capture allocation is bounded; writing a file never drives the guest clock.
V2 run requests complete frames even after guest HALT/BRK/trap or the instruction
cap: idle slots continue devices. A trap still causes a failing CLI exit status.
V1 run termination and State JSON1 stay unchanged. V2 reports State JSON2, adding
profile, slot, IRQ, timer and sample counters to the existing observations.

## Embedding and debugging

`Machine.load` atomically selects the ROM's profile. Reset retains that profile
and ROM but clears CPU/device/slot state. `step` requests one ready transition;
it does nothing on HALT, BRK or trap. `frameAudio(input, cap, output)` completes
one current V2 frame and returns true only on completion. Output is a caller-owned
`[800]i16` value copied before the internal prefix is cleared. No sink/callback
pointer is stored in architectural state. False means no completed output (wrong
profile or exhausted clock). `frame` discards host PCM when unneeded.

`devices` prints profile, slots, IRQ pending/mask/IE/active vector/nesting, timer,
master/voice registers, phases/LFSRs and the buffered PCM prefix. `step`, `trace`,
`history`, `reverse`, source breakpoints and snapshots operate on actual state.
D951 is a blocking mask: bit1 masks its IRQ, bit0 permits it; eligibility is
`pending & ~mask & 3` when IE is true, following the contract's "unmasked" rule.
IRQ entry trace records identify the vector and include all six stack-byte writes.
V2 debugger `frame` completes idle slots after guest stops; a host breakpoint or
watchpoint pauses before completing that requested frame. Full-state history is
retained (maximum32 states), including all audio/timer/IRQ fields. Delta history
has not replaced it; correctness and measured complete restoration take priority.

`savesnap` emits N16S2 only for V2. `loadsnap` requires the same explicitly loaded
profile and payload CRC and clears debugger history after successful commit.
Partial samples, pending IRQs, nested frames and timer state survive exactly.
Previously delivered PCM and SDL queues are host-owned and absent from snapshots.

## Optional SDL playback

```sh
zig build -Dgui=true --search-prefix /path/to/SDL2
zig-out/bin/nova16 run zig-out/demos/interrupt_canvas.n16 --gui --frames 180
```

The SDL sink requests exact48kHz signed16 native-endian mono, callback=NULL,
allowed_changes=0, explicitly starts the device and queues only completed PCM.
Backlog is capped at four frames by dropping host backlog; pause/reset clears
queued samples. Underflow emits host silence; missing/failed audio disables only
the sink. Neither case mutates or accelerates the VM. There is no GUI snapshot
loader; the debugger's snapshot workflow has no SDL queue. SDL tests use a real
dummy audio driver and the real queue API, separately from deterministic headless
PCM and all-pixel renderer/input tests.

## Reproducible verification

```sh
zig build fmt
zig build test --summary all --test-timeout 2m
zig build test -Doptimize=ReleaseSafe --summary all --test-timeout 2m
zig build v2-model-test
python3 scripts/v2_contract_vectors.py
python3 scripts/v2_acceptance.py
```

The independent revision2 fixtures are unchanged. Hardware tests generate the
exact snapshot bytes at137 and20000 slots (including the fixture's acknowledged
VBLANK and edited grayscale palette), and compare the complete800-sample PCM hash.
Other tests cover V1 isolation, transaction rejection, slot boundaries, timer
model sequences, IRQ priority/nesting/IRET faults, allocation ownership and reverse
continuation. `v2_acceptance.py` checks guest-generated WAV/PPM replay hashes,
source breakpoints, snapshots and undo through distributed executables. Demo
reference hashes live in `docs/reliability/v2-demonstrations.json`; `--record` is
an explicit initial-reference/maintainer operation, never a CI repair action.

Compiler/linker optimization, NOVA Studio and V3 hardware remain subsequent work.

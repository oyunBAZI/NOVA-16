# Architecture
NOVA-16 ISA V1 uses eight 16-bit registers, separate PC/SP, and Z/N/C/V flags.
Words are little-endian; instructions and word accesses are even-aligned.
Reset sets registers and flags to zero, SP=BFFE, and PC=E000+ROM entry.

| Range | Role | Permissions |
|---|---|---|
|0000–BFFF|RAM, stack|RWX|
|C000–D7FF|128×96 packed 4bpp framebuffer|RW|
|D800–DFFF|Whitelisted MMIO|Per register|
|E000–FFFF|8 KiB ROM|RX|

CPU, bus and devices have no host I/O. Host applications own file handling,
input injection, pacing and presentation. One frame retires at most 20,000
instructions. The full normative contract is in specification.md.

## State and execution invariants
Machine owns CPU and Bus; Bus owns all guest bytes, input latches, frame counter,
video control and palette. ROM load validates a complete N16R image before reset.
Reset preserves immutable ROM metadata/bytes and clears RAM/VRAM/devices/CPU.
Machine.step clears transient write notifications then attempts one instruction.
Machine.frame samples input, attempts at most isa.frame_budget instructions,
completes one frame counter/latch transition and leaves presentation to the host.

CPU decoding and complete instruction fetch precede operand effects. Effective
addresses are checked in wide arithmetic. Word access preflights both bytes.
CALL validates targets before pushing; RET validates the peeked target before
popping. Stack invariant: SP = BFFE - 2×depth, depth ≤ 24575. All currently
fallible instruction paths precede architectural writes; diagnostic/trap context
is committed on failure and PC/retirement do not advance. This relies on handler
ordering, not a generic memory transaction rollback engine; new instructions
must preserve that ordering and add a fault-atomicity regression.

Core structs remain public for host embedding/tests. Hosts must not mutate private
bookkeeping, immutable ROM bytes/metadata, stop flags or enum tags inconsistently.
Guest instructions cannot modify these host fields. Checked snapshot restoration
is the supported deserialization interface; copying arbitrary native structs is
not a format. Invalid stack depth/reset entry and exhausted retirement counters
now trap rather than causing host arithmetic overflow. Independent stateful tests
compare generated instruction streams against wide reference arithmetic and
separate RAM/stack state. They supplement, rather than replace, boundary vectors.

N16S captures complete deterministic machine state with explicit field widths;
source maps bind to ROM CRC. Trace/history are bounded host tools. State JSON V1
remains an observable report, not a resumable machine snapshot. Timer, SDL, file
and filesystem APIs remain outside all CPU/bus/device execution paths.

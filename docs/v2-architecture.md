# NOVA-16 V2 architecture specification, revision 2

Status: revision2 implementation authorized by the NOVA-16 V2 mission.
Profile2 hardware is implemented on the V2 development branch. See
[v2-implementation.md](v2-implementation.md) for interfaces and
[v2-implementation-ledger.md](v2-implementation-ledger.md) for executed gates.
The arithmetic experiment remains separate; runtime correctness is tested
against the unchanged independent vectors. Architectural tables below remain
normative; historical proposal wording describes the reviewed design.

## Compatibility and activation

V1 files retain exact ISA, device denies, frame timing, State JSON V1 and N16S V1
semantics. A newer executable loading N16R version 1 must select the V1 machine
profile, including rejection of the new opcodes/MMIO below. Never autodetect
extensions from opcode patterns or silently enable devices for an old ROM.

Proposed N16R version 2 keeps the 32-byte little-endian envelope and 8 KiB limit:

| Offset | Bytes | Proposed V2 field |
|---|---:|---|
|0|4|N16R|
|4|2|2|
|6|2|Even entry offset < payload length|
|8|2|Payload length 1–8192|
|10|2|Flags zero|
|12|4|IEEE CRC32 of payload|
|16|2|Machine profile 2|
|18|2|Required features, sound=1 / interrupts=2; profile 2 requires 3|
|20|12|Reserved zero|
|32|length|Unchanged little-endian instruction/data payload at E000|

Unknown version/profile/feature bits fail before changing state. A V1 loader
continues returning BadVersion for V2. Assembler activation must be explicit
(`--architecture nova16-v2` in a future tool); default is V1. Proposed EI, DI,
IRET syntax is rejected in V1. The assembler implements this explicit option and these instructions.

N16S V2 has the exact bounded directory and section formats in
[v2-binary-contract.md](v2-binary-contract.md). That contract also resolves slot,
timer, trap, reset and failure-atomicity details below. The binary contract is
normative when it refines this overview. Independent vectors are checked by
`python scripts/v2_contract_vectors.py`; they are specification fixtures, not a
shipped V2 runtime. V1 snapshots/State JSON remain unchanged.

## Deterministic device clock

Profile 2 proposes 60 logical frames/second and 20,000 transition slots/frame
(1,200,000 slots/second). An instruction or interrupt entry occupies one slot;
retired instructions and accepted interrupt entries have separate counters.
This distinction is explicitly new V2 timing. V1's retired-instruction frame
budget stays unchanged. Timer/audio effects advance only on these slots.
An idle halted/trapped CPU completes frame slots without retiring instructions
when the host explicitly requests a frame. Host pause makes no frame request.
BRK stepping advances only requested transitions; `frame` completes its frame.
These details need approval because they affect V2 observability.

At 48,000 mono PCM samples/second, exactly one sample occurs after every 25th
slot: 800 samples/frame. Device writes commit before the slot-end sample event.
No host timestamps or callback consumption affect phases, pending IRQs or guest
execution. Stepping/debugging and replay use the same transition routine.
Maintain a bounded frame buffer [800]i16 and a 0–24 remainder for partial frames;
N16S V2 records that remainder, phases, LFSRs and pending partial PCM exactly.
A caller-supplied sample sink has explicit ownership and never advances the VM.

## Programmable sound device

Four voices, integer phase accumulator u32 with wrapping addition. Step register
encodes `floor(hertz * 2^32 / 48000)`; legal steps 0–80000000 hex (0–24 kHz).
A zero step holds phase and may produce DC; disable a voice for silence.
Waveforms: square, saw, triangle, deterministic 16-bit LFSR noise. Sample at
current phase, then add step. Noise advances once per enabled sample using
feedback XOR bits 0,2,3,5, shifted into bit 15; reset seed is nonzero
`0xACE1 XOR voice_index`. No floating point, randomness or host entropy.

For each voice: multiply signed waveform by 0–255 volume, divide by 255 toward
zero; sum four i32 voices, divide by four toward zero, multiply by master gain
and divide by 255. Result always fits signed i16. Square uses ±32767; saw is
`(phase >> 16)-32768`; triangle is `2*h-32768` for h<32768, else `98303-2*h`.
Noise uses ±32767 selected by the updated LFSR bit 0. These are simple chip
waveforms with aliasing, not a bandlimited or analog-emulation audio engine.
Disabled voices hold phase/LFSR; master mute preserves enabled oscillator time.

| V2 range | Register and policy |
|---|---|
|D900–D93F|Four 16-byte voice blocks|
|voice+0/+2|Phase step low/high aligned u16, RW|
|voice+4|Volume u8, RW|
|voice+5|Waveform u8 0–3, RW|
|voice+6|Control: enable bit 0; reset-phase/LFSR write strobe bit 1|
|voice+7|Reserved, denied|
|voice+8..11|Current phase u32, byte/aligned-word reads only|
|voice+12..13|LFSR u16, reads only|
|voice+14..15|Reserved, denied|
|D940|Master enable bit 0, reset-all strobe bit 1|
|D941|Master gain u8, RW|
|D942–D945|Read-only low 32 bits of generated sample count|
|D946–D94F|Reserved, denied|

High/low step writes are immediately visible; software wanting atomic changes
must disable the voice, write both halves and re-enable. Every byte/word write
preflights value and both permissions before committing. Reserved control bits
and step > Nyquist trap atomically. Reading control returns enable only, never
retains reset strobes. All these addresses remain denied under V1.

The experiment verifies quarter-cycle vectors, frequency rejection, waveform
bounds, a known LFSR sequence, exact slot/sample ratio and by-value continuation.
It does not validate MMIO, snapshot bytes or audio hardware; those are future
acceptance gates. The model's seed is caller-provided and not a finalized reset
register implementation.

## Optional host playback

Use SDL2's queue mode (null audio callback), requested 48 kHz AUDIO_S16SYS mono
with `allowed_changes=0`; start the initially paused device explicitly. SDL may
perform host-device conversion; deterministic archived PCM remains the VM's
48 kHz i16 stream, with little-endian WAV export independent of host endianness.
Only one host thread queues audio. Cap the host queue to four frames (6,400
bytes), inspect queued byte count and clear/drop host backlog on overrun.
Underflow produces host silence; never accelerate or rewind the guest to repair
playback. Clear queued samples on reset/restore. Mute or missing audio devices
must not change machine state or prevent headless PCM export.

Primary API references, researched for this proposal:
https://wiki.libsdl.org/SDL2/SDL_OpenAudioDevice,
https://wiki.libsdl.org/SDL2/SDL_QueueAudio,
https://wiki.libsdl.org/SDL2/SDL_GetQueuedAudioSize.
SDL queue size is not a precise measure of samples already played by hardware;
it is used only for host buffering, never as a guest clock.

## Interrupt architecture

Proposed V2-only system words: 0006 EI, 0007 DI, 0008 IRET. Other V1 encodings
and flags remain identical. IE is a new CPU bit, reset off; EI takes effect after
its own instruction slot, DI disables before the next boundary. General
registers are not automatically saved. Handler ABI must preserve what it uses.

Eight vectors, little-endian u16 executable addresses at RAM 0040–004F.
IRQ0=frame-complete, IRQ1=programmable slot timer; IRQ2–7 reserved/masked.
V2 IRQ registers D950 pending bitmap (read/write-one-to-clear), D951 mask,
D952 IE observation (read-only), D953 active vector (read-only, FF if none);
D954–D95F reserved. Timer registers D960..D963 period u32 (0 disables),
D964..D967 remaining read-only, D968 control bit0 reload; remaining range denied.
Validate full values before committing; period and timer decrement semantics
must receive separate vectors before code changes. External input initially
remains polled and cannot introduce host-timed interrupts.

At a transition boundary after scheduled device updates, select the lowest
numbered pending unmasked IRQ when IE is true. Coalesce repeated events as one
pending bit. Entry validates vector address/permission and capacity for three
stack words before any write. Push old PC, old ZNCV word, old IE word using the
existing descending checked stack; final top is IE, then flags, then PC. Only
after successful pushes: clear selected pending bit, set active vector, clear
IE and transfer PC. Entry consumes a transition slot, not an instruction retire.
A vector/stack fault traps without consuming pending state or partially pushing.
No automatic nested interrupts; a handler may explicitly EI after saving state.

IRET preflights three words, validates flags/IE reserved bits and return target,
then pops atomically and restores PC/flags/IE. IRET requires an active frame and
current SP equal to that frame's recorded top; ordinary handler pushes/calls
must be unwound first. Active-vector nesting bookkeeping
needs a bounded internal stack (max eight); explicit nested acceptance beyond
that traps before mutation. RET remains a one-word return and does not restore
IE. A handler cannot recover from a corrupted interrupt frame by accidental
partial pop. Debug traces/history record entry/return transitions and source
context; snapshots capture IE/pending/mask/timer/nesting exactly.

Priority vectors: simultaneous frame/timer chooses IRQ0; IRQ1 remains pending;
DI leaves pending bits intact; W1C only acknowledges selected bits. Frame IRQ
is raised at final frame-slot completion and can be entered at the next requested
transition. CPU traps do not themselves generate IRQs or host exceptions.

## Delivered V1 developer platform

The V1 compiler, ABI, guest library and project workflow are now specified in
[language.md](language.md), [guest-abi.md](guest-abi.md), [projects.md](projects.md)
and guest/README.md. Those delivered contracts supersede revision1's tentative
compiler/ABI limits. Crates and Pixel Studio demonstrate ordinary V1 execution.

## Original approval and implementation gates (historical)

1. Separately approve profile2 and the finalized binary/timing/IRQ contract.
2. Add explicit V2 ROM/profile dispatch and independent fixture validation while
   proving every V1 byte/deny/timing golden unchanged. Reject V2 snapshots in V1.
3. Implement headless deterministic audio/MMIO and WAV, compare PCM vectors and
   partial-frame restore across OSs; fuzz all atomic write and snapshot rejects.
4. Implement timer/IRQ entry/IRET with stack/nesting/priority/fault boundaries,
   snapshot/reverse replay and instruction/source diagnostics.
5. Add optional bounded SDL playback queue tests and an explicitly V2 ROM.

No V2 hardware was enabled or implicitly authorized by v0.4. The existing audio
arithmetic model is an isolated experiment, not a delivered device. Network and
filesystem devices are outside this contract.

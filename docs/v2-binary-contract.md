# Profile2 binary and transition contract — revision2

Normative design awaiting separate implementation approval. No shipping loader,
CPU, bus, assembler or debugger implements profile2. All integers below are
little-endian, unsigned unless explicitly signed. Reserved bytes must be zero;
unknown codes/versions/sections are errors. No host structs or implicit padding.
The overview's ROM2/MMIO/oscillator tables apply with these exact refinements.

## ROM and activation

N16R2 is exactly 32+payload_length bytes. Header offsets/widths are the overview
table: entry is an even *offset* into a nonempty payload of at most8192 bytes,
profile=2, features=3, flags=0, reserved=0, IEEE CRC32 of payload. Loading is
all-or-nothing and chooses profile by version, never instructions. A V1 loader
rejects BadVersion before executing or mutating anything. ROM2 resets registers,
clock/devices/IRQs; PC=E000+entry, SP=BFFE, depth=0, IE=0. It pads unused ROM with
zero. The CRC is payload identity, not full-container identity. Switching profile
requires a successful explicit load/reset, never snapshot inference.

## N16S2 envelope and canonical sections

Exactly 67,680 bytes, maximum accepted size also 67,680 (no extensions):

| Offset | Width | Value |
|---|---:|---|
|0|4|N16S|
|4|2|2|
|6|2|0 flags|
|8|4|67680 total file bytes|
|12|4|IEEE CRC32 of bytes32..end|
|16|2|profile2|
|18|2|section count4|
|20|4|directory offset32|
|24|8|zero|
|32|80|Four directory entries,20 bytes each|

Directory entry: tag ASCII4 at0, absolute offset u32 at4, byte length u32 at8,
IEEE section CRC32 u32 at12, reserved u32=0 at16. Exact canonical order/offsets:

| Tag | Offset | Length | Contents |
|---|---:|---:|---|
|CPU2|112|160|V1 metadata plus V2 counters/clock|
|MEM1|272|65584|65536 memory bytes then48 palette bytes|
|AUD1|65856|1696|Audio metadata,4 voices,partial PCM|
|IRQ1|67552|128|Interrupt/timer metadata and8 frames|

No aliases/gaps/overlap/alternate order/duplicates/trailing bytes. Envelope and
all section CRCs checked before semantic decode. CPU2 offsets0..127 are exactly
N16S1's 128-byte metadata described by snapshots.md, including all zeros,
ROM identity/entry/length, stop/trap fields, input/video/frame latches. This keeps
those fields' meanings but expands the trap-code whitelist below. MEM1 bytes
D800..DFFF remain inert memory-shadow bytes, not live MMIO values. ROM padding,
checksum, active-PC executability, even untrapped PC and stack SP/depth must pass
V1 hardening. Stopped aligned denied next-PCs and trapped fault PCs remain legal.
N16S2 may contain only a nonempty ROM2 image, profile2/features3 implied by header;
expected payload CRC must match the currently selected ROM2 before restore.

CPU2 extension:

| Offset | Width | Field |
|---|---:|---|
|128|8|Completed transition slots u64|
|136|8|Accepted IRQ entry count u64|
|144|2|slot in frame0..19999|
|146|2|PCM prefix count0..799|
|148|1|slot remainder0..24|
|149|11|zero|

Let T=slots. slot=T%20000, prefix=floor(slot/25), remainder=T%25,
frame latch=floor(T/20000)%65536, generated PCM count=floor(T/25).
Retired instructions + IRQ entry count <=T, each count cannot exceed T;
validate without overflowing addition. Partial PCM contains exactly prefix
samples, remaining entries zero. Samples already delivered in earlier frames
are host-owned and absent. Transition trace/history/host playback queues and
breakpoint configuration are not serialized. Restore clears those host buffers
only after committing a completely validated candidate.

AUD1: byte0 master enable boolean, byte1 master gain, bytes2..7 zero,
u64 generated sample count at8, bytes16..31 zero. Four16-byte voices at32+16*i:

| Voice offset | Width | Field |
|---|---:|---|
|0|4|phase step0..80000000hex|
|4|4|phase, any u32|
|8|2|nonzero LFSR|
|10|1|volume|
|11|1|wave0 square/1 saw/2 triangle/3 noise|
|12|1|enable boolean|
|13|3|zero|

AUD1 bytes96..1695 are800 signed i16 PCM samples, prefix valid and rest zero.
Reset master disabled, gain255; voices phase/step/volume/wave/enable=0, noise=
ACE1 XOR index. Master/voice reset strobes reset phase and LFSR only, preserving
step/volume/wave/enable/gain/sample count and buffered PCM. Enable bits always
retain the write's bit0. Master disabled freezes all oscillators and emits zero;
master gain0 advances enabled oscillators and emits zero. Noise advances before
selecting its bit; other waveforms sample before phase increment, as the existing
isolated math model specifies. Divide every signed stage toward zero, not floor.

IRQ1 byte0 pending, byte1 mask, byte2 IE boolean, byte3 active depth0..8;
u32 period at4, u32 remaining at8; reload boolean at12; bytes13..15 zero.
Eight12-byte frame records begin at16. Active prefix: top SP u16 at0, vector u8
at2 (0/1), bytes3..11 zero. Inactive records all zero. Bytes112..127 zero.
Pending/mask permit only bits0/1. Depth0 means no active vector, observed FF;
otherwise active vector is last record.vector. Each recorded top is even,
<=BFF8; inner top <= preceding top-6; CPU SP <= innermost top. Stack capacity
is unchanged V1 (SP=BFFE-2*word_depth, depth<=24575), not an ABI RAM restriction.
Stack *contents* can be edited by guest code and are checked when IRET executes;
restore must not silently repair an invalid future return frame. Remaining<=
period, period0 requires remaining0; oneshot expired may have period>0/remain0.

## Slot order and stopping

A requested transition selects exactly one instruction attempt, IRQ entry
attempt, or idle action, then completes one slot. Only a ready CPU (no halt,
pause or trap) accepts IRQs. HALT does not implicitly wake on IRQ in profile2;
there is no WFI opcode in this revision. A host frame request advances the
remaining slots to the next frame boundary even on BRK/HALT/trap, producing
silence/sound and timer events deterministically. A paused host requests none.
An instruction-step request on a stopped CPU does nothing unless explicitly
resumed by the caller; a request cannot silently clear a trap or HALT.

At slot start: choose lowest pending unmasked IRQ if IE, else instruction.
Commit instruction/entry or record its trap (failed operations do not retire).
Then decrement timer, latch its event; advance total slot count; emit sample if
T%25==0 using post-write device state; when T%20000==0, increment frame/vblank,
latch IRQ0, deliver the800 samples to a caller sink and clear partial buffer.
New pending bits can be selected only at the next requested slot. A successful
EI/DI/IRET changes IE before that boundary. Timer ticks on instructions, IRQ
entry, fault and idle slots equally. Debugger stepping uses the identical order.
Before any work, T=maxu64 produces ClockLimit without consuming a slot or
changing devices/counters. IRQ entry count and retirement cannot wrap; a
would-overflow attempt traps before its architectural effects. Its slot still
completes if T permits. Full machine reset is the only clock-count reset.

## Timer and MMIO transactions

D960..D963 reads period; every successful byte/aligned-word write replaces those
bits of the period and immediately re-arms remaining to the resulting u32,
even if unchanged. Period0 disables. Thus a split u32 update can visibly create
an intermediate period; software must account for this. Remaining decrements
if nonzero at slot end. Its 1→0 transition latches IRQ1; reload1 sets remaining=
period immediately, reload0 leaves0 until a period write. D968 bit0 changes
reload without re-arming. D964..D967 remaining is read-only. D969 onward denied.

All MMIO words preflight both bytes and final combined values against a single
old-state view; only then commit all effects. No half reset, acknowledge or
period re-arm on reject. All MMIO reads use one logical view, no read-clear in
new V2 registers. D950 pending accepts W1C bits0/1, mask D951 accepts bits0/1;
other bits ReservedBits. D952/D953 read IE/active vector, writes denied. Word
D950 writes clear/mask together, word D952 reads both observations together.

Step half/byte writes validate the entire resulting step<=80000000hex. Volume
any u8; waveform0..3 else DeviceValue; control bits other than0/1 ReservedBits.
Voice+6/+7 word denied (reserved second byte), before any reset. Read control
returns bit0, strobes never latch. Reserved/read-only permissions follow the
overview; alignment/range faults have existing V1 precedence. Value validation
occurs only after both permissions pass. No new MMIO is accessible in profile1.

## Interrupt entry, return and traps

EI=0006, DI=0007, IRET=0008 only in profile2. Entry preflight order: nesting<8;
vector target even/executable; capacity for3 hardware-stack words. On success
push oldPC, oldflags(ZNCV low4), oldIE(0/1), remember finalSP/vector, clear pending
selected bit, clear IE, set PC target, count accepted entry. R0..R7 untouched.
IRET requires active frame and currentSP==record.top; then reads top IE,flags,PC,
validates reserved bits and even/executable PC, and atomically pops3 words,
restores flags/IE/PC and removes one record. It retires as one instruction.
Priority0 before1; repeated requests coalesce. DI leaves pending intact. W1C
never clears unrelated bits. General registers require a handler ABI save.

Trap codes1..11 retain V1 N16S ordering (InvalidOpcode, Unaligned, ExecuteDenied,
AddressOverflow, ReadDenied, WriteDenied, ReservedBits, StackUnderflow,
StackOverflow, InvalidStack, InstructionLimit). Additional codes:

| Code | Fault | Diagnostic address/access |
|---|---|---|
|12|InvalidInterruptState|SP/stack for no active frame or SP mismatch; offending word address/stack for flags or IE|
|13|InterruptNesting|current SP/stack on ninth entry|
|14|ClockLimit|0/decode on total-slot overflow|
|15|DeviceValue|first invalid addressed register/write|

Bad return/vector target uses Unaligned before ExecuteDenied, address=target,
access=fetch. Entry stack exhaustion StackOverflow, address=SP-6, access=stack.
Instruction faults retain V1 fault PC/instruction. Entry faults use currentPC,
instruction=0; no automatic pending acknowledgement or partial stack/record/IE
change. IRET faults leave SP/depth/record/PC/flags/IE unchanged. Trap reporting
and subsequent slot-end clock/device events are the only permitted mutations
on failure; timer events can still latch pending. T overflow consumes no slot.

## Independent vectors and future gates

`docs/vectors/v2-contract.json` contains exact ROM2/snapshot2 bytes (base64),
SHA256s, PCM signed samples/hash, slot/timer traces and entry/IRET/atomic-reject
examples. `scripts/v2_contract_vectors.py` constructs them with Python struct,
zlib, integer arithmetic and hashlib, independent of Zig structs and mixer.
Default checks equality to committed fixtures and verifies shipping V1 rejects
ROM2/snapshot2 with state unchanged. `--write` is an explicit maintainer action,
never used by CI. These are reviewable specification fixtures, not evidence of
a working V2 loader or hardware. Future implementation must consume these
vectors unchanged or version the reviewed contract explicitly.

# N16S snapshot V1
Fixed-size, portable binary snapshots; no compiler struct layouts or pointers.
Total size: 65,744 bytes. Header: magic N16S (0), u16 version 1 (4), u16 flags
zero (6), u32 payload length 65,712 (8), IEEE payload CRC32 (12), 16 reserved
zero bytes (16). Every integer is little-endian. Payload is metadata (128), all
65,536 bus bytes, then 48 palette bytes. Exact lengths and reserved bits are strict.

Metadata offsets:

| Offset | Type | Field |
|---|---|---|
|0|u32|ROM payload checksum|
|4|u16|Entry offset|
|6|u8|Flags Z/N/C/V; upper bits zero|
|7|u8|bit0 HALT, bit1 BRK pause|
|8|8×u16|R0…R7|
|24,26,28|u16|PC, SP, private stack depth|
|30|2 bytes|Reserved zero|
|32|u64|Retired instruction count|
|40|i32|Diagnostic address|
|44|u16|Last instruction|
|46|u8|Access: fetch/read/write/stack/decode = 0…4|
|47|u8|Trap code; 0 means absent|
|48,50|u16|Trap PC, opcode|
|52|i32|Trap address|
|56|u8|Trap access|
|57,58,59|u8|Held, pressed, display enabled (boolean)|
|60|u16|Frame counter|
|62|u8|VBLANK boolean|
|63|u8|Reserved zero|
|64|u16|Original ROM payload length|
|66|62 bytes|Reserved zero|

Trap codes 1…11: InvalidOpcode, Unaligned, ExecuteDenied, AddressOverflow,
ReadDenied, WriteDenied, ReservedBits, StackUnderflow, StackOverflow,
InvalidStack, InstructionLimit. Absent traps require all trap context bytes zero.
The last code prevents host counter overflow at 2^64−1 retired instructions.

Restore validates ROM CRC/padding/entry, stack bounds and ownership, flags,
enums, booleans, reserved bytes and untrapped PC alignment before committing.
Debugger restores require the currently loaded ROM checksum. Failed restores
leave machine state intact. Symbol maps, breakpoints, watchpoints, trace/undo
history and transient last-write notifications are host debugger configuration,
not machine state; history is cleared on restore. Input latches, video palette,
full RAM/VRAM/ROM, flags, stop/trap context and counters are preserved.

State JSON V1 output is unchanged; N16S is an independent versioned format.

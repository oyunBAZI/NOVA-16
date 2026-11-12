# State JSON schema 1
The runner prints one JSON object to stdout and optionally writes identical
bytes to `--state-json PATH`. Diagnostics/errors go to stderr; a guest trap
returns a nonzero exit code after producing state. Reaching a budget is a normal
stop with halted=false and trapped=false.

| Field | Type | Meaning |
|---|---|---|
|schema_version|integer|1|
|rom_checksum|integer|Unsigned IEEE CRC32 of payload|
|executed_instructions|integer|Retired since reset; traps do not retire|
|frame_count|integer|16-bit emulated frame counter|
|registers|8 integers|R0…R7, unsigned 16-bit|
|pc / sp|integers|Unsigned 16-bit guest addresses|
|flags|integer|Z,N,C,V in bits 0…3|
|halted / paused / trapped|booleans|HALT, BRK and trap status|
|trap|object or null|kind, pc, address (signed for checked overflow), access|
|vram_checksum|integer|IEEE CRC32 of all 6144 packed VRAM bytes|

`--input FILE` accepts ordered zero-based frame numbers and unsigned 8-bit masks,
one pair per line. `#` lines are comments. Bits persist until the next event.
A frame samples input once and executes at most 20,000 instructions. Afterward
it increments the counter modulo 65536 and latches VBLANK. Host time is absent
from headless execution. A screenshot depends on VRAM, palette and display enable;
its PPM SHA-256 can differ even when the raw VRAM checksum is unchanged.

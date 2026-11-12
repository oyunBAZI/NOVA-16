# Bus and devices

| Region | Inclusive addresses | Size | Access |
|---|---|---:|---|
|RAM|0000–BFFF|49152|Read/write/execute|
|Framebuffer|C000–D7FF|6144|Read/write|
|MMIO|D800–DFFF|2048|Whitelisted bytes|
|ROM|E000–FFFF|8192|Read/execute|

Aligned little-endian words preflight both bytes before access. Signed off6
address arithmetic is checked in a wider integer. RAM/VRAM reset to zero; ROM
payload is preserved on reset and padding is zero. Traps record faulting PC,
address, access category and instruction; no host exception escapes guest execution.

| Register | Access | Effect |
|---|---|---|
|D800 KEY_HELD|R|Up,Down,Left,Right,A,B,Start,Select in bits 0–7|
|D801 KEY_PRESSED|R|Latched rising edges; read clears|
|D802 FRAME_LO|R|Low frame byte|
|D803 FRAME_HI|R|High frame byte|
|D804 VIDEO_CTRL|RW|Bit 0 display enable, default 1; reserved bits trap|
|D805 VBLANK|R|Bit 0 frame completed; read clears|
|D820–D84F PALETTE|RW|16 RGB byte triples|

Every undocumented MMIO access and every write to read-only MMIO or ROM traps.
Word reads at D800 clear only KEY_PRESSED; word reads at D804 clear VBLANK.
Word writes at D804 reject atomically. The palette supports aligned word writes.

Memory display in the debugger uses `peek`, which neither clears nor changes
registers. Watchpoints observe both bytes of word stores after instruction execution.

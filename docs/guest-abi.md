# NOVA-16 Guest ABI 1

ABI version 1 is a software convention on unchanged ISA V1; old ROMs need not
adopt it. Eight registers cannot directly read SP, so local activation records
use a separate software frame region addressed by R7. Hardware CALL/RET still
use the ISA's checked descending stack and original encodings.

| Register | Contract |
|---|---|
|R0–R3|Four scalar arguments, left to right; caller-saved|
|R0|Scalar result (u16 bit pattern; i16 uses two's complement; bool 0/1)|
|R1–R3|Additional routine-specific results/status, caller-saved|
|R4–R6|Callee-saved|
|R7|Callee-saved software frame pointer|
|Z/N/C/V|Caller-saved; no flags survive calls unless explicitly promised|

RAM layout (inclusive): 0000–00BF reserved future runtime; 00C0–00EF library
scratch; 00F0–00FF runtime failure record; 0100–3FFF static user words/arrays;
4000–7FFF software frames; 8000–BFFD hardware stack; BFFE initial empty SP.
Static globals are two-byte aligned, zero initialized on machine load/reset.
All scalar fields occupy two bytes, including bool. Struct fields are packed
in declaration order with word alignment; arrays are contiguous words. No heap.
A ROM image may hold constant tables, but mutable globals live in RAM.

Bootstrap sets R7=8000 and CALLs main. A framed function first preserves R4,
R5, R6, R7 with PUSH, then checks old R7>=4100 and subtracts 256. New R7 is the
base of its own 128-word frame. Arguments are copied into initial local slots.
The saved hardware stack layout from current SP is old R7, R6, R5, R4, return
PC; temporary expression/argument pushes go below this and must be balanced.
Epilogue POPs R7/R6/R5/R4 then RETs. Leaf library routines may omit software
frames and preserve only callee-saved registers they actually modify.

At most 64 simultaneous software frames fit. A compiler expression stack is
bounded independently (nesting <=64), so 64 frames × (128 expression bytes +
10 saved/return bytes) fit in the 16 KiB hardware stack reserve. Every call site
must balance its temporaries; the machine still enforces real stack permissions.
Frame overflow records a guest error and BRKs/HALTs; it never writes into static
memory. General assembly may use a different stack convention, but must not be
called as ABI1 without an adapter. There are no stack arguments in ABI1 revision 1.

Library failures return documented status in a caller-saved register and do not
perform denied writes. Compiler runtime errors write a code at 00F0, source
line at 00F2 when available, then BRK followed by HALT. These are actual guest
instructions. ROM overflow (>8192 payload bytes), static data overflow and local
frame overflow are compile errors with source locations. Raw user pointers can
still cause deterministic CPU traps; ABI conventions do not change bus permissions.

`examples/abi_conformance.asm` executes nested calls with distinct saved register
sentinels, separate frame locals and return values. Tests verify R0=49, R4–R6
unchanged, R7=8000, SP=BFFE/depth=0, the two local frames and RAM result. This
is executed by the real CPU, not checked only by parsing the assembly.

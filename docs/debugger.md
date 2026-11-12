# Terminal debugger
`n16dbg ROM [--symbols MAP]` loads the same machine as the runner. With no
map argument it attempts the ROM basename plus `.sym`. Symbols annotate disassembly.
Input can be interactive or piped from a script. Numbers use decimal or `0x` hex.

| Command | Meaning |
|---|---|
|help|List commands|
|regs|Registers, flags, PC/SP and status/trap|
|step [n]|Retire at most n instructions (default 1); resumes BRK|
|continue [budget]|Run until stop or budget (default 1,000,000)|
|break ADDRESS / delete ADDRESS|Set/remove pre-execution breakpoint|
|watch ADDRESS / unwatch ADDRESS|Watch guest writes, showing old/new byte|
|disasm ADDRESS COUNT|Decode up to COUNT instructions with symbols|
|mem ADDRESS LENGTH|Hex/ASCII dump (?? for unmapped registers)|
|stack COUNT|Show active stack words|
|reset|Reset CPU/RAM/devices and preserve loaded ROM|
|saveframe PATH|Write current PPM|
|quit|Exit|

A breakpoint is tested before execution. To pass one use `step` or `delete`;
`continue` at the same address intentionally stops again. BRK advances PC;
subsequent step/continue clears its pause and proceeds. Stepping does not advance
frame counters; use the runner for frame-timed applications. Memory inspection
uses non-destructive device reads and never clears key edges or VBLANK.
Budgets/counts and command lengths are bounded; malformed commands print errors.

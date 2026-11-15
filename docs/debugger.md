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

## Frame-based investigation and deterministic state
- `frame [n]`: advance at most n guest frames (default 1, maximum 1000), respecting
  breakpoints, watchpoints, BRK, HALT and traps. Uses the ISA frame budget.
- `input MASK`: inject held bits deterministically; rising edges latch normally.
  Pipe input/frame commands for replay without host keyboard or time.
- `devices`: peek input/frame/video state and palette without read-clear effects.
- `trace [n]`: inspect up to 128 last executed instructions, opcode/immediate,
  PC, register/SP/flag changes, memory writes and traps.
- `history CAPACITY`: enable 0…32 complete pre-instruction states (default off),
  bounded to about 2 MiB. `history` shows counts. `reverse` restores the latest
  pre-instruction state; branching from history clears the old trace.
- `savesnap PATH` / `loadsnap PATH`: save/restore portable N16S state. Restore
  checks the current ROM and clears trace/undo state; debug break/watch settings stay.
- `source ADDRESS`: show source location from a checked versioned symbol map.

Frames interrupted by a breakpoint/watchpoint complete their one invoked frame,
as the V1 frame contract specifies. Resuming starts a new frame. Reverse restores
pre-instruction machine state, including device latches, and undoes a completed
frame counter if the reversed instruction was its last instruction. It does not
undo host breakpoint settings. See snapshots.md for the byte format.

## Source-oriented commands
Load a checksum-bound JSON source map with `--symbols PROGRAM.sym2`. Then:

```
symbols
break lib/graphics.asm:2
continue 100
source
next
mem result 2
history 8
step
reverse
```

`break FILE:LINE` and `delete FILE:LINE` use exact root-relative paths in the
verified map, selecting the first mapped, decodable executable address on that
line. Missing/invalid locations fail explicitly; no filename guessing occurs.
`source [ADDRESS_OR_SYMBOL]` defaults to PC. Address commands (mem, disasm,
watch, break, source) also accept an exact case-sensitive symbol name whose
value fits a 16-bit address. `symbols` lists the loaded namespace.

`next [budget]` retires until the source file/line changes, a stop condition or
breakpoint occurs, or the bounded instruction budget expires. It advances past
a current breakpoint once, like `step`; it is statement stepping, not function
step-over. Reverse is instruction-level. Traps include the saved encoding,
disassembly, category/access/address and mapped source location. All inspection
uses non-acknowledging reads; no host timer affects execution.


## Deep exact history

`history delta 2048` selects the new bounded delta ring; the maximum is 4096.
`history 32` retains the complete-state mode, and `history 0` disables recording.
The Workbench defaults to 2048 entries natively and 256 in Wasm. Each entry stores
CPU/device/clock/partial-PCM state and original RAM/VRAM write bytes. Frame actions
keep the earliest old byte per address. Device read-clear and failed-instruction
metadata are restored from the complete small state, not guessed from writes.

A separate bounded write journal can evict old whole actions before the entry
limit is reached. An embedding group larger than the entire journal clears
history rather than permit reverse to restore an incomplete action. The bounded
Workbench frame budget fits the journal. Classic CLI instruction-level frame
history semantics remain available. Reversing clears stale forward trace/host
playback; snapshots and ROM formats are unchanged. Measured storage/copy costs
and whole-state reference comparisons are recorded in the evolution evidence.

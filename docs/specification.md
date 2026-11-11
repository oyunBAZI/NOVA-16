# NOVA-16 — Master Implementation Prompt

**Recommended GitHub repository:** nova16-virtual-computer

**Project name:** NOVA-16

**Tagline:** A complete, understandable 16-bit computer built in Zig.

---

## YOUR ROLE AND MISSION

You are the lead systems engineer, CPU architect, emulator developer, toolchain engineer, and test engineer for NOVA-16. Your task is to IMPLEMENT a working, professionally organized open-source 16-bit virtual computer, not merely produce a plan, architecture sketch, README, or scaffolding.

Build an original fictional computer and all of its essential software: a documented instruction set, executable CPU emulator, memory bus, graphics device, input device, assembler, ROM format, terminal debugger, graphical host application, bootable example programs, and thorough automated tests.

The primary implementation language is Zig. Target approximately 10,000–12,000 meaningful lines of Zig source code, assembly examples, and tests. This is a scope estimate, not a quota. Never pad the codebase, duplicate generated code, or sacrifice quality to reach a line count.

Work incrementally through the phases below. After each phase, run relevant checks, fix failures, commit coherent changes if repository access is available, and continue to the next phase. Do not report a milestone as passed without showing the successful test or demonstration proving it passed. Do not stop after documenting the project.

This is an emulator/virtual computer. Do not claim to have produced a physical CPU, a silicon design, a PC-compatible BIOS, a Linux-compatible architecture, or a conventional general-purpose operating system. A “bootable ROM” here means a validated NOVA-16 ROM container which the emulator loads, resets into, and executes.

## 1. TECHNOLOGY AND BOUNDARIES

1. Use Zig version **0.17.1** as the pinned initial toolchain version. Keep build scripts and source compatible with that exact version. Document the pinned release in README and CI. Do not silently use Zig master or copy snippets from incompatible older Zig APIs.
2. Write the CPU, bus, devices, ROM loader, assembler, disassembler, debugger, and command-line programs in Zig.
3. Use SDL2 via its C ABI for the optional desktop graphical frontend. Avoid external emulator cores and large game engines. The virtual machine must remain completely independent of SDL2.
4. The default headless build and tests must succeed without SDL2 installed. Enable SDL2 integration with a deliberate graphical-build option; document its dependencies.
5. Provide Linux support as the primary tested platform. Add macOS and Windows build support where practical; label any untested platforms honestly.
6. Core execution must be deterministic. Avoid host time, random numbers, filesystem operations, SDL2, and global mutable state inside CPU, bus, and device logic.
7. Prefer small modules, explicit ownership, error unions, bounded buffers, and meaningful tests. No network access is needed at runtime.
8. Never download or execute untrusted ROMs automatically. The user explicitly supplies local ROM files.
9. License original project code under MIT if establishing a new repository is authorized. Respect any dependencies' licenses.
10. If a GitHub remote and permission are configured, push completed, tested work to its main branch. Otherwise, create a complete local Git repository with informative commits and report what remains to publish. Never force-push, overwrite unrelated content, or presume credentials.

## 2. REQUIRED DELIVERABLES

By the end, the repository must contain:

- A working 16-bit CPU emulator implementing the precise ISA below.
- A complete 64 KiB memory address space with ROM, RAM, VRAM, and MMIO.
- A deterministic 128×96, 16-color display with a palette register bank.
- A keyboard/controller input device with held and rising-edge key states.
- A validated .n16 ROM container and loader.
- A two-pass assembler with labels, directives, proper error diagnostics, and symbol maps.
- A disassembler that round-trips with the assembler for all supported opcodes.
- A terminal debugger with stepping, breakpoints, watchpoints, memory inspection, and disassembly.
- A GUI runner that scales the display without filtering and accepts keyboard input.
- A headless runner that produces machine-readable final state and a PPM screenshot.
- At least four real bootable ROM demonstrations written in NOVA-16 assembly.
- Unit, integration, end-to-end, property-style, and negative tests.
- A CI workflow and precise reproduction instructions.
- An architecture manual, ISA reference, memory map, ROM format specification, assembler manual, debugger guide, and milestone ledger.

## 3. ARCHITECTURAL CONTRACT — FREEZE THIS BEFORE IMPLEMENTATION

The following V1 machine model is normative. Do not make incompatible changes merely to simplify code. If a genuine ambiguity is discovered, make the smallest consistent decision, document it in docs/decisions.md, and add a regression test.

### 3.1 CPU state

- Architecture name: NOVA-16, ISA version 1.
- Eight general-purpose unsigned 16-bit registers: R0 through R7.
- Separate 16-bit program counter PC.
- Separate 16-bit stack pointer SP.
- Status flags Z (zero), N (negative/sign bit), C (carry/no-borrow), V (signed overflow).
- Instruction words and 16-bit data words use little-endian byte order.
- Memory is byte-addressed with 16-bit addresses, for 65,536 addressable bytes.
- Instruction addresses must be even; invalid alignment causes an explicit machine trap.
- Instructions are either 2 or 4 bytes long.
- On reset: R0–R7 = 0, flags = 0, SP = 0xBFFE, halted = false, and PC = 0xE000 + ROM entry offset.
- Arithmetic is modulo 2^16. Explicitly compute carry and signed overflow flags.
- A trap records its kind, faulting PC, address if relevant, and useful diagnostic details. It stops guest execution cleanly; it must never crash the host.

### 3.2 Exact memory map

| Address range | Size | Purpose | Access |
| --- | ---: | --- | --- |
| 0x0000–0xBFFF | 48 KiB | General RAM, executable programs, stack | Read/write/execute |
| 0xC000–0xD7FF | 6 KiB | Packed video framebuffer | Read/write, not execute |
| 0xD800–0xDFFF | 2 KiB | Memory-mapped I/O | Whitelisted registers only |
| 0xE000–0xFFFF | 8 KiB | Boot ROM | Read/execute, never write |

Implement bus.read8, bus.write8, bus.read16, bus.write16, and instruction fetch APIs.

- Word accesses must use even effective addresses and stay within a valid readable/writable region. Unaligned or crossing accesses trap.
- RAM and VRAM initialize to zero on machine reset.
- ROM is padded with 0x00 when the payload uses fewer than 8,192 bytes.
- Writes to ROM trap. Writes to undocumented MMIO addresses trap, rather than silently succeeding.
- Instruction fetch from VRAM or MMIO traps. Fetch from RAM or ROM is allowed.
- Address calculation for loads and stores must detect out-of-range signed offsets instead of silently wrapping.
- Memory access errors must report the access type, address, and current PC.
- CPU instructions may not reach directly into host process memory.

### 3.3 Stack contract

- Stack grows downward in RAM, beginning with SP = 0xBFFE.
- PUSH: first subtract 2 from SP, then store the 16-bit value little-endian at SP.
- POP: read the 16-bit value at SP, then add 2 to SP.
- CALL pushes the return PC after full instruction decoding.
- RET pops PC and validates that the target is an aligned executable address.
- PUSHF and POPF encode only Z, N, C, V into bits 0, 1, 2, 3 respectively; reserved bits zero.
- An empty-stack POP/RET, stack overflow, invalid SP, or stack access into non-RAM must cause a machine trap.
- Keep private host-side stack-depth accounting if needed to detect true empty-stack operations. Do not expose this bookkeeping as a guest register.

## 4. EXACT INSTRUCTION SET ENCODING

Each instruction begins with a 16-bit W0. The top nibble W0[15:12] is the major opcode. For major opcodes 0x1–0xC, except where stated, destination register is bits [11:9], source/base register is [8:6], and bits [5:0] must be zero for register-only instructions. If an instruction takes W1, that second 16-bit word is encoded immediately after W0.

Do not permit nonzero reserved bits. They are invalid encodings and must trap rather than produce accidental aliases.

### 4.1 Major opcodes

| Major opcode | Assembly | Encoding and semantics |
| --- | --- | --- |
| 0x0 | System | Exact 16-bit instruction words listed below |
| 0x1 | MOV Rd, Rs | Rd ← Rs; flags unchanged |
| 0x2 | LDI Rd, imm16 | W1 = immediate; flags unchanged |
| 0x3 | ADD Rd, Rs | Rd ← Rd + Rs; set Z,N,C,V |
| 0x4 | SUB Rd, Rs | Rd ← Rd − Rs; set Z,N,C,V |
| 0x5 | AND Rd, Rs | Bitwise AND; set Z,N; clear C,V |
| 0x6 | OR Rd, Rs | Bitwise OR; set Z,N; clear C,V |
| 0x7 | XOR Rd, Rs | Bitwise XOR; set Z,N; clear C,V |
| 0x8 | CMP Rd, Rs | Compute Rd − Rs for flags only |
| 0x9 | LDW Rd, [Rs + off6] | Load aligned little-endian 16-bit word |
| 0xA | STW Rd, [Rs + off6] | Store low/high bytes of Rd |
| 0xB | LDB Rd, [Rs + off6] | Load one byte, zero-extend to 16 bits |
| 0xC | STB Rd, [Rs + off6] | Store low 8 bits of Rd |
| 0xD | B.cond target | Conditional PC-relative branch described below |
| 0xE | Control | Absolute and register jumps/calls described below |
| 0xF | Extended ALU | Shifts, arithmetic helpers, and stack operations below |

For LDW, STW, LDB, and STB: off6 is W0[5:0], a signed six-bit displacement measured in **bytes**, in the inclusive range −32 through +31. Effective address = base register value + signed off6, with checked address arithmetic. Word operations require the final address to be even. STW and STB store the register encoded as Rd; Rs is the base-address register.

### 4.2 System exact words

| Word | Mnemonic | Behavior |
| --- | --- | --- |
| 0x0000 | NOP | Do nothing |
| 0x0001 | HALT | Permanently halt guest until reset |
| 0x0002 | BRK | Stop in debugger after advancing PC |
| 0x0003 | RET | Pop return address into PC |
| 0x0004 | PUSHF | Push packed status flags |
| 0x0005 | POPF | Pop and restore packed flags |

All other 0x0 words are invalid in V1.

### 4.3 Branch instruction

W0 = 0xD000 | (condition << 8) | (signed 8-bit displacement encoded as u8).

After decoding this 2-byte instruction, if the condition is true, PC ← next_PC + displacement × 2. The displacement therefore counts 16-bit instruction words, not bytes. Reject out-of-address-space or odd targets. The assembler resolves label addresses and rejects offsets outside −128…+127.

Condition codes:

| Code | Name | Meaning |
| --- | --- | --- |
| 0 | AL | Always |
| 1 | EQ | Z |
| 2 | NE | not Z |
| 3 | CS | C |
| 4 | CC | not C |
| 5 | MI | N |
| 6 | PL | not N |
| 7 | VS | V |
| 8 | VC | not V |
| 9 | HI | C and not Z |
| A | LS | not C or Z |
| B | GE | N == V |
| C | LT | N != V |
| D | GT | not Z and N == V |
| E | LE | Z or N != V |
| F | — | Invalid/reserved |

### 4.4 Control group 0xE

W0[11:8] is subopcode. W0[7:5] is Rn for register forms; W0[4:0] must be zero. Absolute forms require W0[7:0] = 0.

- Subopcode 0: JMP address16; W1 is absolute target.
- Subopcode 1: CALL address16; W1 is absolute target.
- Subopcode 2: JMPR Rn; PC = register value.
- Subopcode 3: CALLR Rn; push next_PC, then PC = register value.
- Subopcodes 4–15 are invalid in V1.

All branch/jump/call targets must be even and fetchable RAM/ROM addresses. For a faulting CALL, perform target validation before modifying the guest stack, so the trap does not leave a half-executed call.

### 4.5 Extended ALU 0xF

W0[11:8] is subopcode, W0[7:5] is Rd, W0[4:2] is Rs, W0[1:0] must be zero. Unary forms require Rs = 0.

| Subcode | Mnemonic | Semantics |
| --- | --- | --- |
| 0 | SHL Rd, Rs | Logical left shift by Rs & 15 |
| 1 | SHR Rd, Rs | Logical right shift by Rs & 15 |
| 2 | SAR Rd, Rs | Arithmetic signed right shift by Rs & 15 |
| 3 | NOT Rd | Bitwise complement |
| 4 | MUL Rd, Rs | Low 16 bits of unsigned product |
| 5 | TEST Rd, Rs | Bitwise AND to flags, no store |
| 6 | ADDI Rd, imm16 | W1 added to Rd |
| 7 | CMPI Rd, imm16 | W1 compared with Rd |
| 8 | PUSH Rd | Push register word |
| 9 | POP Rd | Pop register word |
| A | INC Rd | Add 1 |
| B | DEC Rd | Subtract 1 |
| C–F | — | Invalid/reserved |

Set Z from a zero 16-bit result and N from bit 15. ADD/ADDI/INC set C for a 17-bit carry and V for signed overflow. SUB/CMP/CMPI/DEC set C when no unsigned borrow occurred (left operand ≥ right operand); compute V using proper two's-complement subtraction overflow. Logical operations, NOT, and TEST clear C and V. MUL sets C if the unsigned full 32-bit product exceeds 0xFFFF and clears V. Shifts set C to the last bit shifted out and clear V; for a zero shift count, preserve C while recomputing Z,N and clearing V. Loads, stores, MOV, LDI, stack moves, and control transfers leave flags unchanged unless explicitly specified.

All instruction handlers must be tested against edge cases: 0x0000, 0x0001, 0x7FFF, 0x8000, 0xFFFF, carry, borrow, signed overflow, zero shifts, shift-by-15, malformed opcodes, and invalid addresses.

## 5. ROM CONTAINER FORMAT

Use extension .n16 and a strict 32-byte little-endian header followed by raw ROM bytes.

| Offset | Length | Field |
| --- | ---: | --- |
| 0 | 4 | ASCII magic: N16R |
| 4 | 2 | Format version: 1 |
| 6 | 2 | Entry offset into 8 KiB ROM; even |
| 8 | 2 | Payload length in bytes; 1–8192 |
| 10 | 2 | Flags: 0 in V1 |
| 12 | 4 | Standard IEEE CRC-32 of payload |
| 16 | 16 | Reserved, all zero |
| 32 | Variable | ROM payload, exactly payload_length bytes |

Loader must validate magic, version, length, total exact file size, reserved fields, checksum, even entry offset, and entry < payload_length. Reject truncated headers, trailing bytes, corrupt payloads, and oversize images with useful diagnostics. Map payload at 0xE000; zero-fill unused ROM. Set reset PC to 0xE000 + entry offset. Define stable error codes.

## 6. GRAPHICS SYSTEM

Implement a deterministic 128×96 pixel, 16-color display:

- VRAM is exactly 6,144 bytes at 0xC000–0xD7FF.
- Two pixels per byte; even X uses low nibble, odd X uses high nibble.
- Pixel byte index = Y × 64 + floor(X / 2).
- Palette entries are 24-bit RGB values stored in MMIO.
- Default palette is a fixed, documented array of 16 RGB triples, identical across machines.
- A host-side renderer converts the current VRAM/palette to an RGB image. The core must be usable without any windowing libraries.
- Support PPM P6 screenshot output with exact 128×96 dimensions and deterministic bytes.
- GUI window defaults to integer 4× scaling (512×384), with nearest-neighbor pixels and no filtering. User can choose another positive integer scale.

### 6.1 MMIO register definitions

| Address | Name | Behavior |
| --- | --- | --- |
| 0xD800 | KEY_HELD | Read-only 8-bit currently held buttons |
| 0xD801 | KEY_PRESSED | Read-only latched rising edges; clears on read |
| 0xD802 | FRAME_LO | Read-only low byte of 16-bit frame count |
| 0xD803 | FRAME_HI | Read-only high byte of 16-bit frame count |
| 0xD804 | VIDEO_CTRL | Read/write bit 0: display enabled; default 1 |
| 0xD805 | VBLANK | Read-only bit 0: frame completed since last read; clears on read |
| 0xD820–0xD84F | PALETTE | 16 RGB triples in order R,G,B |

Unsupported MMIO addresses trap on guest access. Writes to read-only registers trap. On VIDEO_CTRL writes, reject nonzero reserved bits. If display is disabled, present palette entry 0 as the entire output but retain VRAM untouched. The host presents the image after each completed emulated frame.

KEY_HELD bit order: bit 0 Up, 1 Down, 2 Left, 3 Right, 4 A, 5 B, 6 Start, 7 Select. KEY_PRESSED latches 0→1 transitions since its last read. Host keys: arrow keys, Z, X, Enter, and Right Shift, respectively.

### 6.2 Frame model

Define a frame as **20,000 retired guest instructions**, not hardware-accurate CPU cycles. On each headless or GUI frame:

1. Sample and inject the eight input bits.
2. Execute up to 20,000 guest instructions, stopping earlier on HALT, BRK, trap, or debugger pause.
3. Increment the 16-bit frame counter once (modulo 65,536).
4. Latch VBLANK = 1.
5. Convert VRAM/palette into a host image and optionally present it.

The graphical frontend should aim for 60 presented frames per wall-clock second, but wall-clock pacing must live outside core emulation. The headless frontend must run without waiting for real time. Given the same ROM, frame count, input schedule, and initial state, results must be identical. Clearly document this simplified timing model; do not claim cycle accuracy.

## 7. TWO-PASS ASSEMBLER

Provide a separate n16asm executable. Required syntax:

- Comments beginning with semicolon.
- Case-insensitive mnemonics and register names.
- Labels of the form name:, including forward references.
- Decimal, 0x-prefixed hex, 0b-prefixed binary, and signed literals where appropriate.
- Simple constant expressions: literal, label, symbol, plus or minus numeric constant.
- Register operands R0 through R7.
- Loads/stores like LDW R1, [R2 + 4], where the displacement is in bytes.
- Relative branches like B.EQ loop and B.AL start.
- Directives .org, .entry, .equ, .byte, .word, .ascii, .fill, and .align.
- .org is a monotonically increasing absolute ROM address within 0xE000–0xFFFF and fills gaps with zero. Reject backward/overlapping .org.
- .entry accepts a ROM label/address; default entry is the first emitted instruction. Validate it is an even address inside emitted payload.
- Strict width, displacement, symbol, alignment, reserved-bit, and address validation.
- Diagnostics must include source filename, line, column where practical, offending token, and explanation.
- Generate .n16 with CRC-32 and optional .sym address-to-symbol map.
- Provide deterministic output: assembling identical input twice yields identical bytes.
- Add a disassembler that prints canonical assembly or, where unknown data prevents perfect round-trip, a lossless .word representation.
- Tests must prove every supported opcode can be assembled, decoded, executed where relevant, and disassembled.

Do not implement a full C compiler, linker, macro preprocessor, or elaborate package manager in V1.

## 8. DEBUGGER

Provide n16dbg as a terminal debugger using the same machine core, with at least these commands:

- help — list all commands.
- regs — show R0–R7, PC, SP, flags, and execution status.
- step [n] — execute n instructions, default one.
- continue [max_instructions] — run until breakpoint, watchpoint, HALT, BRK, trap, or bounded instruction budget.
- break ADDRESS — set breakpoint before the instruction at ADDRESS.
- delete ADDRESS — remove breakpoint.
- watch ADDRESS — break on write to an address, including VRAM and supported MMIO.
- unwatch ADDRESS — remove watchpoint.
- disasm ADDRESS COUNT — display decoded instructions and addresses.
- mem ADDRESS LENGTH — show hex bytes and ASCII.
- stack COUNT — show stack words from SP.
- reset — reset and reload the same ROM.
- saveframe PATH — write current framebuffer as PPM.
- quit — terminate.

Breakpoints must trigger before an instruction executes. Watchpoints trigger on matching guest writes and explain old/new values. BRK pauses execution after advancing PC so continued execution does not endlessly break on the same BRK. The debugger should display loaded .sym labels where available. Robustly reject malformed commands; no panics for user mistakes.

## 9. FRONTENDS AND COMMAND-LINE CONTRACT

Create three executables:

1. nova16 — machine launcher and headless/GUI runner.
2. n16asm — assembler.
3. n16dbg — interactive debugger.

The following commands are acceptance targets. If Zig installation or target-platform conventions require a minor syntax difference, document the exact working equivalents and test them.

    zig build
    zig build test
    zig build -Dgui=true
    zig-out/bin/n16asm examples/boot_splash.asm --out zig-out/demos/boot_splash.n16 --symbols zig-out/demos/boot_splash.sym
    zig-out/bin/nova16 inspect zig-out/demos/boot_splash.n16
    zig-out/bin/nova16 run zig-out/demos/boot_splash.n16 --headless --frames 120 --screenshot zig-out/demo.ppm --state-json zig-out/demo.json
    zig-out/bin/nova16 run zig-out/demos/boot_splash.n16 --gui --scale 4
    zig-out/bin/n16dbg zig-out/demos/boot_splash.n16

Build the headless application and assembler by default. The -Dgui=true option compiles SDL2 support. If a binary without GUI support receives --gui, return a helpful error instead of crashing. In CLI usage, mutually exclusive options must fail clearly. Never use unlimited guest execution by default in CI; support an explicit max-instructions safety cap.

The state JSON must include ROM checksum, executed instruction count, frame count, R0–R7, PC, SP, flags, halted/trapped status, and a deterministic VRAM checksum. Use a stable schema and document it.

## 10. REQUIRED BOOTABLE EXAMPLES

Implement all four as actual NOVA-16 assembly sources, assemble them during the build, and test their observable output.

1. boot_splash.asm — boots, sets palette colors, fills the framebuffer with a visibly recognizable multicolor pattern and logo/wordmark or geometric design; stops or loops intentionally.
2. bouncing_pixel.asm — animates a 4×4 sprite or ball over multiple frames using FRAME_LO/HI or VBLANK polling; visibly moves and reverses at display boundaries.
3. paint.asm — a keyboard-controlled pixel cursor using arrows, A to paint, B to erase, and Start to clear the drawing. Poll input registers through MMIO.
4. diagnostics.asm — runs register, memory, flag, load/store, branch, and stack checks, then writes a clearly distinguished success or failure pattern to VRAM; document expected registers and framebuffer checksums.

The V1 machine has no built-in text font, DMA engine, sprite engine, or graphics command processor. Programs manipulate the 4bpp framebuffer themselves. Do not fake sample visuals in the host renderer: they must come from guest instructions writing VRAM or palette registers.

Where a sample program needs a small utility routine, make it real assembly that runs on the documented CPU. A boot demo is not complete until the emulator executes its generated .n16 file end-to-end.

## 11. PROJECT STRUCTURE

Use approximately the following structure. Adapt filenames to current Zig conventions, but preserve separation of responsibilities:

    nova16-virtual-computer/
      README.md
      LICENSE
      build.zig
      build.zig.zon
      .github/workflows/ci.yml
      src/
        arch/isa.zig
        core/cpu.zig
        core/bus.zig
        core/machine.zig
        core/traps.zig
        devices/video.zig
        devices/input.zig
        rom/format.zig
        asm/lexer.zig
        asm/parser.zig
        asm/assembler.zig
        asm/encoder.zig
        debug/disasm.zig
        debug/debugger.zig
        frontend/sdl2.zig
        cli/nova16_main.zig
        cli/assembler_main.zig
        cli/debugger_main.zig
      examples/
        boot_splash.asm
        bouncing_pixel.asm
        paint.asm
        diagnostics.asm
      tests/
        isa_tests.zig
        cpu_tests.zig
        bus_tests.zig
        rom_tests.zig
        asm_tests.zig
        video_tests.zig
        integration_tests.zig
      docs/
        architecture.md
        isa.md
        memory-map.md
        rom-format.md
        assembler.md
        debugger.md
        development.md
        decisions.md
        roadmap.md

No giant single-file implementation. Place architectural constants in one authoritative module, and import or generate docs/test expectations from that shared definition wherever sensible. Avoid duplicate handwritten opcode tables that drift.

## 12. DEVELOPMENT PHASES — COMPLETE IN ORDER

### Phase 0 — Reproducible repository foundation

- Initialize Git repository and build system for Zig 0.17.1.
- Create architecture manual, ISA table, roadmap, and clean folder layout.
- Add formatting, test, and build tasks.
- Provide a zero-dependency headless hello-world executable.
- Gate: fresh clone can run zig build and zig build test successfully.

### Phase 1 — ISA decoder and executable CPU skeleton

- Implement CPU state, instruction fetch/decode, reset, NOP, HALT, invalid-opcode trap.
- Enforce even PCs, instruction lengths, and reserved bits.
- Construct raw-byte unit test programs.
- Gate: deterministic PC stepping, valid reset state, and safe traps.

### Phase 2 — Arithmetic, branches, and stack

- Implement all ALU, shift, comparison, branch, jump, call, return, push/pop, and flag logic.
- Test a complete arithmetic truth table at critical boundaries.
- Gate: recursive or nested call test, branch condition matrix, and overflow tests all pass.

### Phase 3 — Memory bus, devices, and ROM loading

- Implement map, permissions, stack bounds, .n16 parser, checksum, and controlled machine reset.
- Test RAM execution, ROM write protection, non-MMIO traps, and malformed ROMs.
- Gate: a raw encoded boot ROM loads, writes RAM, and HALTs with correct registers.

### Phase 4 — Assembler and disassembler

- Implement lexical analysis, parsing, symbol pass, emission pass, diagnostics, ROM packing, and .sym files.
- Use the assembler to build all machine-test fixtures.
- Gate: every instruction encodes/decodes correctly; forward labels and branch ranges work; input errors produce useful messages.

### Phase 5 — Video and headless screenshots

- Implement 4bpp VRAM, palette MMIO, RGB conversion, PPM output, and deterministic state JSON.
- Assemble and execute boot_splash.
- Gate: screenshot dimensions and hash match a checked-in expected result; palette and nibble order tests pass.

### Phase 6 — Input and deterministic frame runtime

- Implement held/pressed input, VBLANK latching, frame counter, and 20,000-instruction budgeting.
- Assemble animation and keyboard samples.
- Gate: scripted input sequences reproduce identical final state and frame hash; changed inputs produce expected state differences.

### Phase 7 — SDL2 graphical frontend

- Create responsive pixel-perfect window with scalable dimensions, keyboard input, pause/reset, and clean shutdown.
- Ensure core runs with no SDL dependency when graphical mode is disabled.
- Gate: visible running boot_splash, animated motion, and interactive paint demo; record an actual screenshot or short capture if environment permits.

### Phase 8 — Terminal debugger

- Implement required command set, breakpoints, watchpoints, disassembly, symbol names, and safe error handling.
- Gate: scripted debugger sessions prove break-before-execute, write watchpoint, stepping, stack inspection, and BRK resume behavior.

### Phase 9 — Four polished ROMs

- Finish all four assembly demos and document key controls and expected output.
- Add end-to-end tests for ROM boot, successful diagnostics, framebuffer hashes, and scripted inputs.
- Gate: examples are built from source and genuinely execute without special host-side behavior.

### Phase 10 — Production-grade finish

- Refactor duplicated code, handle all malformed input, clean documentation, add troubleshooting, and improve CLI usability.
- Add GitHub Actions build/test/format checks for the pinned compiler. Build optional SDL2 target in a CI job with system dependency installation, and use a virtual display for smoke tests when practical.
- Produce release artifacts or clear release build instructions. Document actual tested platforms.
- Gate: fresh-clone verification succeeds, no known critical defects remain, demos are reproducible, and the README accurately reflects achieved functionality.

## 13. TEST ENGINEERING REQUIREMENTS

Do not equate “compiles” with “works.” Required validation layers:

1. Decoder table tests for every legal major/subopcode and representative illegal/reserved encodings.
2. Arithmetic and flag reference tests using a simple mathematically independent oracle, particularly signed/unsigned edge cases.
3. Instruction sequencing tests for 2/4-byte operations and control transfers.
4. Bus read/write permission tests covering every boundary: 0xBFFF/0xC000, 0xD7FF/0xD800, 0xDFFF/0xE000, and 0xFFFF.
5. ROM corruption tests: bad magic, CRC, versions, illegal offsets, truncated and oversized payloads.
6. Assembler golden-byte tests and symbol/forward-reference tests.
7. Round-trip assemble/disassemble tests wherever defined, and explicit handling for unknown data.
8. Video pixel packing tests, including pixel (0,0), (1,0), (127,95), palette updates, and display disable.
9. KEY_PRESSED read-clear and edge-transition tests.
10. Stack underflow, overflow, RET target, and CALL atomicity tests.
11. Deterministic replay: same ROM + same ordered input frames = same state JSON and framebuffer checksum.
12. End-to-end boot tests for every included demo, not host-rendered stand-ins.
13. Fuzz/property-style tests for malformed ROM bytes and assembler tokens, bounded by instruction/time limits. Never let malformed guest data crash the host.

Include a small reference ISA test vector document with instruction bytes, initial CPU state, expected final state, and trap outcomes. A reviewer must be able to inspect at least ten vectors manually.

CI must run zig fmt --check (or the working equivalent for pinned Zig), zig build, zig build test, assembler/demo builds, headless sample runs, and ROM checks. No false green results: do not silence failures with ignored exit codes.

## 14. ENGINEERING BUDGET

Aim for this rough, adjustable allocation of source code plus tests:

| Area | Target LOC |
| --- | ---: |
| CPU core, decoder, and ISA behavior | 1,800 |
| Bus, MMIO, and machine state | 1,200 |
| Video, input, and SDL2 frontend | 1,400 |
| Assembler and disassembler | 2,200 |
| Debugger | 1,400 |
| ROM format, CLI, and runtime | 1,000 |
| Assembly demo programs | 800 |
| Automated tests | 1,700 |
| **Total illustrative budget** | **11,500** |

These are planning figures, not pass/fail targets. Correctness and maintainability matter more than exact LOC.

## 15. README, DOCUMENTATION, AND PRESENTATION

The README should immediately explain what NOVA-16 is, show the architecture at a glance, and include:

- One-sentence project pitch and features that truly work.
- Status badges only for actual running CI jobs.
- A screenshot generated from a working ROM, once one exists.
- A compact memory map and ISA summary.
- Supported operating systems and exact compiler version.
- Quick-start steps from a fresh clone.
- Example assembler, runner, headless screenshot, and debugger commands.
- Controls for interactive sample ROMs.
- A truthful “implemented / planned” checklist and version roadmap.
- Design philosophy, limitations, and links to detailed docs.
- Contributing/test instructions and license.

Produce thoughtful terminal output and legible documentation. Do not add fake benchmarks, fabricated screenshots, or unverified feature claims.

## 16. OUT OF SCOPE FOR V1

Do NOT inflate the project into:

- x86, ARM, RISC-V, Game Boy, or PC compatibility.
- Hardware synthesis into an FPGA or physical silicon.
- Cycle-perfect emulation or DMA.
- A full multitasking kernel, filesystem, networking stack, Unix shell, C compiler, or native window manager.
- Sound synthesis, sprites, elaborate GPU acceleration, or 3D graphics.
- A web-based cloud service or user-account system.

Those can be V2 extensions only after all V1 acceptance gates pass. Preserve extensibility, but finish the defined V1 product first.

## 17. AGENT OPERATING RULES AND REPORT FORMAT

1. Begin by inspecting the repository and toolchain. If empty, create the full structure. If it already contains work, preserve and incorporate it without destroying user changes.
2. Show a concise execution plan linked to the numbered phases, then IMPLEMENT. Do not repeatedly ask permission for ordinary in-scope coding decisions.
3. Keep the architectural contract stable across modules, tests, documentation, and examples.
4. After each phase, run all relevant commands. Fix regressions before progressing.
5. Update docs/roadmap.md with completion criteria, evidence, and actual test command results.
6. Make small meaningful commits with phase-oriented messages. Push only to an authorized, configured remote.
7. If time or environment limits stop work, leave a compilable checkpoint, record incomplete items exactly, and provide the next command/action. Never declare unfinished phases complete.
8. Distinguish tested facts from estimates and aspirations.
9. Report blockers with precise technical cause and the safest path to resolution.
10. Favor working, integrated code over speculative architectural prose.

At every checkpoint, report:

- Completed phase(s) and actual implemented features.
- Commit hash(es) if commits were created.
- Exact tests/build commands run and their pass/fail results.
- A booted ROM and observable output, where applicable.
- Remaining acceptance criteria and next highest-priority engineering work.
- Whether changes were pushed, and to which remote/branch if verified.

## FINAL DEFINITION OF DONE

The project is complete only if a new developer can clone the repository, install the pinned Zig toolchain, execute the documented commands, assemble a sample .asm source into .n16, load and boot it, see the resulting picture or deterministic PPM image, use keyboard input in the GUI, open the terminal debugger, step through real guest instructions, and run a green automated test suite. The four examples must be powered by the emulated ISA, not hard-coded host application demonstrations.

Begin now. Implement Phase 0, verify its acceptance gate, proceed to Phase 1, and keep moving in order until NOVA-16 V1 genuinely passes its definition of done.

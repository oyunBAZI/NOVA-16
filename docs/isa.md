# ISA V1

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


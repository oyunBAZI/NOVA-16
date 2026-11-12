; On success R7=0x600d and all pixels are green (palette 11).
; On failure R7=0xdead and all pixels are red (palette 6).
.entry start
start:
    LDI R7, 0
    LDI R0, 0xffff
    LDI R1, 1
    ADD R0, R1
    B.EQ zero
    JMP fail
zero:
    B.CS carry
    JMP fail
carry:
    LDI R0, 0x7fff
    ADD R0, R1
    B.VS overflow
    JMP fail
overflow:
    B.MI negative
    JMP fail
negative:
    SUB R0, R1
    B.VS sub_overflow
    JMP fail
sub_overflow:
    CMPI R0, 0x7fff
    B.EQ arithmetic_ok
    JMP fail
arithmetic_ok:
    LDI R2, 0x0200
    LDI R3, 0xabcd
    STW R3, [R2 + 2]
    LDW R4, [R2 + 2]
    CMP R3, R4
    B.EQ word_ok
    JMP fail
word_ok:
    LDB R4, [R2 + 3]
    CMPI R4, 0xab
    B.EQ endian_ok
    JMP fail
endian_ok:
    LDI R4, 0x12
    STB R4, [R2 + 2]
    LDW R4, [R2 + 2]
    CMPI R4, 0xab12
    B.EQ bytes_ok
    JMP fail
bytes_ok:
    LDI R0, 0
    CMP R0, R1
    PUSHF
    LDI R0, 4
    MUL R0, R1
    POPF
    B.CC flags_ok
    JMP fail
flags_ok:
    PUSH R3
    LDI R3, 0
    POP R5
    CMPI R5, 0xabcd
    B.EQ stack_ok
    JMP fail
stack_ok:
    CALL outer
    CMPI R6, 2
    B.EQ calls_ok
    JMP fail
calls_ok:
    LDI R0, 0x8001
    LDI R1, 15
    SAR R0, R1
    CMPI R0, 0xffff
    B.EQ shift_ok
    JMP fail
shift_ok:
    LDI R0, 3
    LDI R1, 5
    OR R0, R1
    CMPI R0, 7
    B.EQ or_ok
    JMP fail
or_ok:
    XOR R0, R1
    AND R0, R1
    TEST R0, R0
    B.EQ logic_ok
    JMP fail
logic_ok:
    LDI R7, 0x600d
    LDI R1, 0xbb
    JMP fill
fail:
    LDI R7, 0xdead
    LDI R1, 0x66
fill:
    LDI R0, 0xc000
fill_loop:
    STB R1, [R0]
    INC R0
    CMPI R0, 0xd800
    B.NE fill_loop
    HALT
outer:
    LDI R6, 0
    CALL inner
    INC R6
    RET
inner:
    INC R6
    RET

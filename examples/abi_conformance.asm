; ABI1 executable contract: separate software frames and hardware return stack.
.entry abi_start
abi_start:
    LDI R7, 0x8000
    LDI R4, 0x4444
    LDI R5, 0x5555
    LDI R6, 0x6666
    LDI R0, 19
    LDI R1, 23
    CALL abi_outer
    LDI R2, 0x0100
    STW R0, [R2]
    HALT
abi_outer:
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    LDI R4, 256
    SUB R7, R4
    STW R0, [R7]
    STW R1, [R7 + 2]
    LDI R4, 0xaaaa
    LDI R5, 0xbbbb
    LDI R6, 0xcccc
    CALL abi_inner
    ; Inner must have preserved both the caller's frame pointer and saved regs.
    LDW R1, [R7]
    ADD R0, R1
    LDW R1, [R7 + 2]
    ADD R0, R1
    POP R7
    POP R6
    POP R5
    POP R4
    RET
abi_inner:
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    LDI R4, 256
    SUB R7, R4
    LDI R0, 7
    STW R0, [R7]
    LDI R4, 0
    LDI R5, 0
    LDI R6, 0
    POP R7
    POP R6
    POP R5
    POP R4
    RET

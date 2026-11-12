; ABI1 checked RAM/VRAM memory operations, no scratch. R4-R7 preserved.
; zero(R0 destination,R1 byte count) -> R3 status. Empty range is a no-op.
n16_memzero:
    PUSH R4
    CMPI R1, 0
    B.EQ n16_zero_ok
    MOV R4, R0
    ADD R4, R1
    B.CS n16_zero_bad
    CMPI R4, 0xd800
    B.HI n16_zero_bad
    LDI R2, 0
n16_zero_loop:
    STB R2, [R0]
    INC R0
    DEC R1
    B.NE n16_zero_loop
n16_zero_ok:
    LDI R3, 0
    POP R4
    RET
n16_zero_bad:
    LDI R3, 1
    POP R4
    RET
; copy(R0 dst,R1 src,R2 bytes) -> R0 original dst,R3 status; overlap safe.
n16_memcopy:
    PUSH R0
    PUSH R4
    PUSH R5
    PUSH R6
    CMPI R2, 0
    B.EQ n16_copy_ok
    MOV R4, R0
    ADD R4, R2
    B.CS n16_copy_bad
    CMPI R4, 0xd800
    B.HI n16_copy_bad
    CMPI R1, 0xe000
    B.CS n16_copy_rom
    MOV R4, R1
    ADD R4, R2
    B.CS n16_copy_bad
    CMPI R4, 0xd800
    B.HI n16_copy_bad
    B.AL n16_copy_direction
n16_copy_rom:
    MOV R4, R1
    NOT R4
    INC R4
    CMP R2, R4
    B.HI n16_copy_bad
n16_copy_direction:
    MOV R6, R2
    LDI R5, 1
    CMP R0, R1
    B.LS n16_copy_loop
    MOV R4, R1
    ADD R4, R2
    CMP R0, R4
    B.CS n16_copy_loop
    ADD R0, R2
    ADD R1, R2
    DEC R0
    DEC R1
    LDI R5, -1
n16_copy_loop:
    LDB R4, [R1]
    STB R4, [R0]
    ADD R0, R5
    ADD R1, R5
    DEC R6
    B.NE n16_copy_loop
n16_copy_ok:
    LDI R3, 0
    B.AL n16_copy_done
n16_copy_bad:
    LDI R3, 1
n16_copy_done:
    POP R6
    POP R5
    POP R4
    POP R0
    RET
; load/store word reject odd/MMIO/denied addresses before touching memory.
n16_load_word:
    LDI R3, 1
    TEST R0, R3
    B.NE n16_memory_return
    CMPI R0, 0xd800
    B.CC n16_load_ok
    CMPI R0, 0xe000
    B.CC n16_memory_return
n16_load_ok:
    LDW R0, [R0]
    LDI R3, 0
    RET
n16_store_word:
    LDI R3, 1
    TEST R0, R3
    B.NE n16_memory_return
    CMPI R0, 0xd800
    B.CS n16_memory_return
    STW R1, [R0]
    LDI R3, 0
n16_memory_return:
    RET
; array_get(base,index,count) -> value/status. Word arrays, <=8192 elements.
n16_array_get:
    LDI R3, 1
    CMPI R2, 8192
    B.HI n16_memory_return
    CMP R1, R2
    B.CS n16_memory_return
    ADD R1, R1
    ADD R0, R1
    B.CS n16_memory_return
    JMP n16_load_word
; array_set(base,index,count,value) -> status R3.
n16_array_set:
    PUSH R4
    MOV R4, R3
    LDI R3, 1
    CMPI R2, 8192
    B.HI n16_array_done
    CMP R1, R2
    B.CS n16_array_done
    ADD R1, R1
    ADD R0, R1
    B.CS n16_array_done
    MOV R1, R4
    CALL n16_store_word
n16_array_done:
    POP R4
    RET

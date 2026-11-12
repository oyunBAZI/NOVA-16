; Guest ABI1 arithmetic. R4-R7 preserved. No scratch memory.
; udiv: R0 numerator,R1 divisor -> R0 quotient,R1 remainder,R2 status(0/1 zero).
n16_udiv:
    PUSH R4
    PUSH R5
    PUSH R6
    MOV R4, R0
    MOV R5, R1
    CMPI R5, 0
    B.NE n16_div_nonzero
    LDI R0, 0
    MOV R1, R4
    LDI R2, 1
    JMP n16_div_done
n16_div_nonzero:
    LDI R6, 0
    LDI R2, 0
    LDI R3, 16
    LDI R0, 1
n16_div_bit:
    SHL R6, R0
    SHL R4, R0
    LDI R1, 0
    B.CC n16_div_lowbit
    LDI R1, 1
n16_div_lowbit:
    SHL R2, R0
    B.CS n16_div_wide
    OR R2, R1
    CMP R2, R5
    B.CC n16_div_next
    B.AL n16_div_subtract
n16_div_wide:
    OR R2, R1
n16_div_subtract:
    SUB R2, R5
    INC R6
n16_div_next:
    DEC R3
    B.NE n16_div_bit
    MOV R0, R6
    MOV R1, R2
    LDI R2, 0
n16_div_done:
    POP R6
    POP R5
    POP R4
    RET
; Signed division truncates toward zero; -32768/-1 wraps to 8000, status=2.
n16_sdiv:
    PUSH R4
    PUSH R5
    PUSH R6
    LDI R4, 0
    LDI R5, 0
    LDI R6, 0
    CMPI R0, 0x8000
    B.NE n16_sdiv_sign
    CMPI R1, 0xffff
    B.NE n16_sdiv_sign
    LDI R6, 2
n16_sdiv_sign:
    CMPI R0, 0
    B.GE n16_sdiv_den
    LDI R3, 0
    SUB R3, R0
    MOV R0, R3
    LDI R4, 1
    LDI R5, 1
n16_sdiv_den:
    CMPI R1, 0
    B.GE n16_sdiv_call
    LDI R3, 0
    SUB R3, R1
    MOV R1, R3
    LDI R3, 1
    XOR R4, R3
n16_sdiv_call:
    CALL n16_udiv
    CMPI R2, 0
    B.NE n16_sdiv_done
    CMPI R4, 0
    B.EQ n16_sdiv_rem
    LDI R3, 0
    SUB R3, R0
    MOV R0, R3
n16_sdiv_rem:
    CMPI R5, 0
    B.EQ n16_sdiv_status
    LDI R3, 0
    SUB R3, R1
    MOV R1, R3
n16_sdiv_status:
    MOV R2, R6
n16_sdiv_done:
    POP R6
    POP R5
    POP R4
    RET
n16_umod:
    CALL n16_udiv
    MOV R0, R1
    RET
n16_smod:
    CALL n16_sdiv
    MOV R0, R1
    RET
; Checked operations leave wrapping result in R0, status R2=overflow.
n16_uadd_checked:
    ADD R0, R1
    LDI R2, 0
    B.CC n16_arith_return
    LDI R2, 1
    RET
n16_sadd_checked:
    ADD R0, R1
    LDI R2, 0
    B.VC n16_arith_return
    LDI R2, 1
    RET
n16_umul_checked:
    MUL R0, R1
    LDI R2, 0
    B.CC n16_arith_return
    LDI R2, 1
    RET
n16_u8_checked:
    LDI R2, 0
    CMPI R0, 255
    B.LS n16_arith_return
    LDI R2, 1
    RET
n16_unsigned_checked:
    LDI R2, 0
    CMPI R0, 0
    B.GE n16_arith_return
    LDI R2, 1
n16_arith_return:
    RET
n16_ucmp:
    CMP R0, R1
    B.EQ n16_cmp_equal
    B.CC n16_cmp_less
    LDI R0, 1
    RET
n16_scmp:
    CMP R0, R1
    B.EQ n16_cmp_equal
    B.LT n16_cmp_less
    LDI R0, 1
    RET
n16_cmp_less:
    LDI R0, -1
    RET
n16_cmp_equal:
    LDI R0, 0
    RET
n16_usub_checked:
    SUB R0, R1
    LDI R2, 0
    B.CS n16_usub_done
    LDI R2, 1
n16_usub_done:
    RET
n16_ssub_checked:
    SUB R0, R1
    LDI R2, 0
    B.VC n16_ssub_done
    LDI R2, 1
n16_ssub_done:
    RET
n16_signed_checked:
    LDI R2, 0
    CMPI R0, 32767
    B.LS n16_signed_done
    LDI R2, 1
n16_signed_done:
    RET
n16_bool:
    CMPI R0, 0
    LDI R0, 0
    B.EQ n16_bool_done
    LDI R0, 1
n16_bool_done:
    RET

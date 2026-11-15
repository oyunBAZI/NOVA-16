; NOVA-16 profile2 helpers; ordinary guest instructions, no host calls.
; voice: R0 block address, R1 step low, R2 step high, R3 volume|wave<<8,
; R4 final enable/reset bits. Preserves all registers, flags unchanged.
n16v2_voice:
    PUSH R5
    LDI R5, 0
    STB R5, [R0 + 6]
    STW R1, [R0]
    STW R2, [R0 + 2]
    STW R3, [R0 + 4]
    STB R4, [R0 + 6]
    POP R5
    RET
; timer: R0 period low, R1 high, R2 reload. Clobbers R3; flags unchanged.
; The split period writes intentionally rearm each half per hardware contract.
n16v2_timer:
    LDI R3, 0xd960
    STW R0, [R3]
    STW R1, [R3 + 2]
    STB R2, [R3 + 8]
    RET

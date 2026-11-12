; Four guest-programmed voices, timer-driven eight-note melody.
.entry start
start:
    DI
    LDI R0, 0xd900
    LDI R1, 0xb7a3
    LDI R2, 0x0165
    LDI R3, 180
    LDI R4, 3
    CALL n16v2_voice
    LDI R0, 0xd910
    LDI R1, 0x8f5c
    LDI R2, 0x01c2
    LDI R3, 632
    LDI R4, 3
    CALL n16v2_voice
    LDI R0, 0xd920
    LDI R1, 0x35ee
    LDI R2, 0x0217
    LDI R3, 356
    LDI R4, 3
    CALL n16v2_voice
    LDI R0, 0xd930
    LDI R1, 0xd70a
    LDI R2, 0x00a3
    LDI R3, 792
    LDI R4, 3
    CALL n16v2_voice
    LDI R0, 0xd940
    LDI R1, 0xb401
    STW R1, [R0]
    LDI R0, timer_handler
    LDI R1, 0x42
    STW R0, [R1]
    LDI R0, 0x49f0
    LDI R1, 2
    LDI R2, 1
    CALL n16v2_timer
    LDI R0, 0xd951
    LDI R1, 1
    STB R1, [R0]
    EI
main_loop:
    B.AL main_loop

timer_handler:
    PUSH R0
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    LDI R0, 0x100
    LDW R1, [R0]
    INC R1
    STW R1, [R0]
    LDI R2, 7
    AND R1, R2
    LDI R2, 2
    SHL R1, R2
    LDI R0, melody
    ADD R0, R1
    LDW R1, [R0]
    LDW R2, [R0 + 2]
    LDI R3, 0xd900
    LDI R4, 0
    STB R4, [R3 + 6]
    STW R1, [R3]
    STW R2, [R3 + 2]
    LDI R4, 1
    STB R4, [R3 + 6]
    POP R4
    POP R3
    POP R2
    POP R1
    POP R0
    IRET
melody:
    .word 0xb7a3, 0x0165
    .word 0x6872, 0x0191
    .word 0x8f5c, 0x01c2
    .word 0x35ee, 0x0217
    .word 0xbf25, 0x0258
    .word 0x35ee, 0x0217
    .word 0x8f5c, 0x01c2
    .word 0x6872, 0x0191

.include "lib/v2.asm"

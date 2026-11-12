; ABI1 input/runtime. Scratch: E2 previous held word. R4-R7 preserved.
n16_buttons:
    LDI R0, 0xd800
    LDB R0, [R0]
    RET
; Returns held R0, hardware-latched presses R1, releases since last poll R2.
n16_input_poll:
    LDI R3, 0x00e2
    LDW R2, [R3]
    CALL n16_buttons
    STW R0, [R3]
    MOV R3, R0
    NOT R3
    AND R2, R3
    LDI R1, 0xd801
    LDB R1, [R1]
    RET
n16_frame:
    LDI R0, 0xd802
    LDW R0, [R0]
    RET
; wait_frame(previous) -> new frame. No host clock.
n16_wait_frame:
    MOV R1, R0
n16_frame_poll:
    CALL n16_frame
    CMP R0, R1
    B.EQ n16_frame_poll
    RET
; Caller-owned seed: full-period 16-bit LCG, new seed returned R0.
n16_random:
    LDI R1, 25173
    MUL R0, R1
    ADDI R0, 13849
    RET
; Increment a caller-owned animation counter and wrap at a nonzero period.
n16_counter:
    INC R0
    CMP R0, R1
    B.CC n16_counter_done
    LDI R0, 0
n16_counter_done:
    RET

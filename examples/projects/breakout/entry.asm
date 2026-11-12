; NOVA BREAKOUT — ISA V1 only. Every game operation runs on the guest CPU.
.entry start
start:
    LDI R7, state
    CALL title_screen
    LDI R0, 0
    STW R0, [R7]
    LDI R0, 0xffff
    STW R0, [R7 + 18]
wait_frame:
    LDI R0, 0xd802
    LDW R1, [R0]
    LDW R2, [R7 + 18]
    CMP R1, R2
    B.EQ wait_frame
    STW R1, [R7 + 18]
    LDI R0, 0xd801
    LDB R1, [R0]
    LDI R2, 64
    TEST R1, R2
    B.EQ check_mode
    LDW R0, [R7]
    CMPI R0, 1
    B.EQ check_mode
    CALL new_game
check_mode:
    LDW R0, [R7]
    CMPI R0, 1
    B.NE wait_frame
    CALL play_frame
    JMP wait_frame

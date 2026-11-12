new_game:
    CALL clear_screen
    LDI R0, 1
    STW R0, [R7]
    LDI R0, 28
    STW R0, [R7 + 2]
    LDI R0, 3
    STW R0, [R7 + 12]
    LDI R0, 0
    STW R0, [R7 + 14]
    LDI R0, 24
    STW R0, [R7 + 16]
    LDI R5, bricks
    LDI R6, 0
new_brick:
    LDI R4, 1
    STB R4, [R5]
    CALL brick_rectangle
    CALL rectangle
    INC R5
    INC R6
    CMPI R6, 24
    B.NE new_brick
    ; Playfield border.
    LDI R0, 0
    LDI R1, 12
    LDI R2, 64
    LDI R3, 1
    LDI R4, 0x22
    CALL rectangle
    LDI R2, 1
    LDI R3, 83
    CALL rectangle
    LDI R0, 63
    CALL rectangle
    CALL serve
    CALL hud
    RET
serve:
    LDI R0, 32
    STW R0, [R7 + 4]
    LDI R0, 80
    STW R0, [R7 + 6]
    LDI R0, 1
    STW R0, [R7 + 8]
    LDI R0, -1
    STW R0, [R7 + 10]
    RET
play_frame:
    ; Erase last paddle/ball without clearing the whole framebuffer.
    LDI R4, 0
    CALL paddle_rectangle
    CALL rectangle
    CALL ball_rectangle
    CALL rectangle
    LDI R0, 0xd800
    LDB R1, [R0]
    LDW R0, [R7 + 2]
    LDI R2, 4
    TEST R1, R2
    B.EQ try_right
    CMPI R0, 1
    B.EQ try_right
    DEC R0
try_right:
    LDI R2, 8
    TEST R1, R2
    B.EQ paddle_done
    CMPI R0, 55
    B.EQ paddle_done
    INC R0
paddle_done:
    STW R0, [R7 + 2]
    LDW R0, [R7 + 4]
    LDW R1, [R7 + 6]
    LDW R2, [R7 + 8]
    LDW R3, [R7 + 10]
    ADD R0, R2
    ADD R1, R3
    CMPI R0, 1
    B.HI wall_right
    LDI R0, 1
    LDI R2, 1
wall_right:
    CMPI R0, 62
    B.CC wall_top
    LDI R0, 62
    LDI R2, -1
wall_top:
    CMPI R1, 14
    B.HI paddle_test
    LDI R1, 14
    LDI R3, 1
paddle_test:
    CMPI R3, 1
    B.NE save_ball
    CMPI R1, 84
    B.NE bottom_test
    LDW R5, [R7 + 2]
    DEC R5
    CMP R0, R5
    B.CC bottom_test
    ADDI R5, 9
    CMP R0, R5
    B.CS bottom_test
    LDI R3, -1
    ADDI R5, -4
    LDI R2, 1
    CMP R0, R5
    B.CS save_ball
    LDI R2, -1
bottom_test:
    CMPI R1, 94
    B.CC save_ball
    LDW R0, [R7 + 12]
    DEC R0
    STW R0, [R7 + 12]
    B.EQ lose_game
    CALL serve
    CALL hud
    JMP draw_actors
save_ball:
    STW R0, [R7 + 4]
    STW R1, [R7 + 6]
    STW R2, [R7 + 8]
    STW R3, [R7 + 10]
    CALL collide_bricks
    LDW R0, [R7]
    CMPI R0, 1
    B.NE frame_done
 draw_actors:
    LDI R4, 0xdd
    CALL paddle_rectangle
    CALL rectangle
    LDI R4, 0xff
    CALL ball_rectangle
    CALL rectangle
frame_done:
    RET
lose_game:
    LDI R0, 2
    STW R0, [R7]
    CALL end_screen
    RET
; Compute brick geometry from index R6, preserving index/pointer R5/R6.
brick_rectangle:
    PUSH R5
    PUSH R6
    MOV R0, R6
    LDI R1, 0
brick_row:
    CMPI R0, 8
    B.CC brick_column
    ADDI R0, -8
    ADDI R1, 8
    B.AL brick_row
brick_column:
    LDI R2, 8
    MUL R0, R2
    INC R0
    ADDI R1, 18
    LDI R2, 6
    LDI R3, 4
    ; Three distinct colored rows.
    LDI R4, 0x66
    CMPI R1, 18
    B.EQ brick_geometry_done
    LDI R4, 0x99
    CMPI R1, 26
    B.EQ brick_geometry_done
    LDI R4, 0xbb
brick_geometry_done:
    POP R6
    POP R5
    RET
collide_bricks:
    LDI R5, bricks
    LDI R6, 0
collision_loop:
    LDB R0, [R5]
    CMPI R0, 0
    B.EQ collision_next
    CALL brick_rectangle
    PUSH R5
    LDW R4, [R7 + 4]
    DEC R0
    CMP R4, R0
    B.CC collision_no
    ADDI R0, 7
    CMP R4, R0
    B.CS collision_no
    LDW R4, [R7 + 6]
    DEC R1
    CMP R4, R1
    B.CC collision_no
    ADDI R1, 5
    CMP R4, R1
    B.CS collision_no
    POP R5
    LDI R4, 0
    STB R4, [R5]
    CALL brick_rectangle
    LDI R4, 0
    CALL rectangle
    LDW R0, [R7 + 10]
    LDI R1, 0
    SUB R1, R0
    STW R1, [R7 + 10]
    LDW R0, [R7 + 14]
    INC R0
    STW R0, [R7 + 14]
    LDW R0, [R7 + 16]
    DEC R0
    STW R0, [R7 + 16]
    B.EQ win_game
    CALL hud
    RET
collision_no:
    POP R5
collision_next:
    INC R5
    INC R6
    CMPI R6, 24
    B.NE collision_loop
    RET
win_game:
    LDI R0, 3
    STW R0, [R7]
    CALL end_screen
    RET

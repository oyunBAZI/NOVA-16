; glyph(x,y,ASCII32..90), selected color, 3x5 clipped pixels. R3 status.
n16_glyph:
    PUSH R4
    PUSH R5
    PUSH R6
    CMPI R2, 32
    B.CC n16_glyph_bad
    CMPI R2, 90
    B.HI n16_glyph_bad
    ADDI R2, -32
    LDI R3, 5
    MUL R2, R3
    ADDI R2, n16_font_data
    MOV R5, R2
    LDI R6, 5
    PUSH R0
n16_glyph_row:
    LDB R4, [R5]
    LDI R3, 4
    TEST R4, R3
    B.EQ n16_glyph_col2
    CALL n16_glyph_pixel
n16_glyph_col2:
    INC R0
    LDI R3, 2
    TEST R4, R3
    B.EQ n16_glyph_col3
    CALL n16_glyph_pixel
n16_glyph_col3:
    INC R0
    LDI R3, 1
    TEST R4, R3
    B.EQ n16_glyph_next
    CALL n16_glyph_pixel
n16_glyph_next:
    POP R0
    PUSH R0
    INC R1
    INC R5
    DEC R6
    B.NE n16_glyph_row
    POP R0
    LDI R3, 0
    B.AL n16_glyph_done
n16_glyph_bad:
    LDI R3, 1
n16_glyph_done:
    POP R6
    POP R5
    POP R4
    RET
n16_glyph_pixel:
    LDI R2, 0x00e0
    LDB R2, [R2]
    CALL n16_pixel
    RET
; number(x,y,u16), five-or-fewer digits, selected color. R3 status.
n16_number:
    PUSH R4
    PUSH R5
    PUSH R6
    MOV R4, R0
    MOV R5, R1
    MOV R0, R2
    LDI R6, 0
n16_number_digit:
    LDI R1, 10
    CALL n16_udiv
    ADDI R1, 48
    PUSH R1
    INC R6
    CMPI R0, 0
    B.NE n16_number_digit
n16_number_draw:
    POP R2
    MOV R0, R4
    MOV R1, R5
    CALL n16_glyph
    ADDI R4, 4
    DEC R6
    B.NE n16_number_draw
    LDI R3, 0
    POP R6
    POP R5
    POP R4
    RET

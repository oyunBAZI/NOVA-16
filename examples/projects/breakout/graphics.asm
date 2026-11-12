; Rectangle: byte-column x R0, y R1, width R2, height R3, color R4.
; Preserves all registers. Coordinates are checked by game algorithms.
rectangle:
    PUSH R0
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    LDI R5, 64
    MUL R1, R5
    ADD R1, R0
    ADDI R1, 0xc000
rectangle_row:
    MOV R5, R1
    MOV R6, R2
rectangle_column:
    STB R4, [R5]
    INC R5
    DEC R6
    B.NE rectangle_column
    ADDI R1, 64
    DEC R3
    B.NE rectangle_row
    POP R6
    POP R5
    POP R4
    POP R3
    POP R2
    POP R1
    POP R0
    RET
clear_screen:
    LDI R0, 0xc000
    LDI R1, 0
    LDI R2, 3072
clear_word:
    STW R1, [R0]
    ADDI R0, 2
    DEC R2
    B.NE clear_word
    RET
paddle_rectangle:
    LDW R0, [R7 + 2]
    LDI R1, 86
    LDI R2, 8
    LDI R3, 2
    RET
ball_rectangle:
    LDW R0, [R7 + 4]
    LDW R1, [R7 + 6]
    LDI R2, 1
    LDI R3, 2
    RET
title_screen:
    CALL clear_screen
    LDI R0, 6
    LDI R1, 24
    LDI R2, title_text
    LDI R4, 0xdd
    CALL draw_text
    LDI R0, 4
    LDI R1, 42
    LDI R2, subtitle_text
    LDI R4, 0xff
    CALL draw_text
    LDI R0, 10
    LDI R1, 66
    LDI R2, start_text
    LDI R4, 0xee
    CALL draw_text
    RET
end_screen:
    CALL clear_screen
    LDI R0, 12
    LDI R1, 30
    LDI R2, lost_text
    LDI R4, 0x66
    LDW R5, [R7]
    CMPI R5, 3
    B.NE end_words
    LDI R2, won_text
    LDI R4, 0xbb
end_words:
    CALL draw_text
    LDI R0, 10
    LDI R1, 66
    LDI R2, start_text
    LDI R4, 0xee
    CALL draw_text
    CALL hud
    RET
hud:
    LDI R0, 1
    LDI R1, 1
    LDI R2, 62
    LDI R3, 10
    LDI R4, 0
    CALL rectangle
    LDI R0, 2
    LDI R1, 1
    LDI R2, score_text
    LDI R4, 0xff
    CALL draw_text
    LDW R2, [R7 + 14]
    LDI R0, 24
    CALL number_text
    LDI R0, 36
    LDI R2, lives_text
    LDI R4, 0xdd
    CALL draw_text
    LDW R2, [R7 + 12]
    LDI R0, 56
    ADDI R2, 48
    CALL glyph
    RET
number_text:
    LDI R3, 48
number_tens:
    CMPI R2, 10
    B.CC number_digits
    ADDI R2, -10
    INC R3
    B.AL number_tens
number_digits:
    PUSH R2
    MOV R2, R3
    CALL glyph
    ADDI R0, 4
    POP R2
    ADDI R2, 48
    CALL glyph
    RET
; Null-terminated ASCII, 3x5 glyphs doubled vertically, 4 byte-columns apart.
draw_text:
    PUSH R0
    PUSH R2
    PUSH R3
text_character:
    LDB R3, [R2]
    CMPI R3, 0
    B.EQ text_done
    PUSH R2
    MOV R2, R3
    CALL glyph
    POP R2
    INC R2
    ADDI R0, 4
    B.AL text_character
text_done:
    POP R3
    POP R2
    POP R0
    RET
glyph:
    PUSH R0
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    ADDI R2, -32
    LDI R3, 5
    MUL R2, R3
    ADDI R2, font_data
    LDI R5, 64
    MUL R1, R5
    ADD R0, R1
    ADDI R0, 0xc000
    MOV R1, R0
    ADDI R1, 64
glyph_row:
    LDB R5, [R2]
    LDI R6, 4
    TEST R5, R6
    B.EQ glyph_second
    STB R4, [R0]
    STB R4, [R1]
glyph_second:
    INC R0
    INC R1
    LDI R6, 2
    TEST R5, R6
    B.EQ glyph_third
    STB R4, [R0]
    STB R4, [R1]
glyph_third:
    INC R0
    INC R1
    LDI R6, 1
    TEST R5, R6
    B.EQ glyph_next
    STB R4, [R0]
    STB R4, [R1]
glyph_next:
    ADDI R0, 126
    ADDI R1, 126
    INC R2
    DEC R3
    B.NE glyph_row
    POP R6
    POP R5
    POP R4
    POP R3
    POP R2
    POP R1
    POP R0
    RET

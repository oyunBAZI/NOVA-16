; NOVA-16: diagonal tiled field and central geometric NOVA insignia.
.entry start
start:
    LDI R0, 0xd820
    LDI R1, 8
    STB R1, [R0]
    LDI R1, 12
    STB R1, [R0 + 1]
    LDI R1, 24
    STB R1, [R0 + 2]
    LDI R0, 0xc000
    LDI R1, 0
    LDI R2, 16
    LDI R4, 4
row:
    LDI R3, 64
column:
    MOV R5, R1
    AND R5, R2
    MOV R6, R0
    AND R6, R2
    XOR R5, R6
    SHR R5, R4
    LDI R6, 0x11
    MUL R5, R6
    ADDI R5, 0x22
    STB R5, [R0]
    INC R0
    DEC R3
    B.NE column
    INC R1
    CMPI R1, 96
    B.NE row
; 48x32 diamond, built one packed byte at a time.
    LDI R0, 0xc81c
    LDI R1, 16
    LDI R2, 2
    LDI R3, 0xff
upper:
    MOV R4, R2
    MOV R5, R0
line:
    STB R3, [R5]
    INC R5
    DEC R4
    B.NE line
    ADDI R0, 63
    ADDI R2, 2
    DEC R1
    B.NE upper
    LDI R1, 16
lower:
    MOV R4, R2
    MOV R5, R0
line2:
    STB R3, [R5]
    INC R5
    DEC R4
    B.NE line2
    ADDI R0, 65
    ADDI R2, -2
    DEC R1
    B.NE lower
; Render NOVA-16 using a compact ROM-resident 3x5 font, centered above diamond.
; Each glyph occupies three bits of a row; each bit becomes a 2-pixel cell.
    LDI R0, text
    LDI R1, 0xc2d2
    LDI R2, 7
glyph:
    PUSH R1
    LDI R3, 5
glyph_row:
    LDB R4, [R0]
    INC R0
    LDI R5, 4
    LDI R6, 3
glyph_bit:
    TEST R4, R5
    B.EQ blank
    LDI R7, 0xdd
    STB R7, [R1]
blank:
    INC R1
    PUSH R7
    LDI R7, 1
    SHR R5, R7
    POP R7
    DEC R6
    B.NE glyph_bit
    ADDI R1, 61
    DEC R3
    B.NE glyph_row
    POP R1
    ADDI R1, 4
    DEC R2
    B.NE glyph
    HALT
text:
    .byte 5,7,7,7,5 ; N
    .byte 7,5,5,5,7 ; O
    .byte 5,5,5,5,2 ; V
    .byte 2,5,7,5,5 ; A
    .byte 0,0,7,0,0 ; -
    .byte 2,6,2,2,7 ; 1
    .byte 7,4,7,5,7 ; 6

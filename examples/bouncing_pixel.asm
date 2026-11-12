; 4x4 ball, x advances two pixels per frame, y one. Reverses at all edges.
; R0=x/2 (0..62), R1=y (0..92), R2=dx, R3=dy. R7=last frame.
.entry start
start:
    LDI R0, 0
    LDI R1, 0
    LDI R2, 1
    LDI R3, 1
    LDI R7, 0xffff
wait:
    LDI R4, 0xd802
    LDW R5, [R4]
    CMP R5, R7
    B.EQ wait
    MOV R7, R5
    LDI R6, 0
    CALL draw
    ADD R0, R2
    ADD R1, R3
    CMPI R0, 62
    B.NE left
    LDI R2, -1
left:
    CMPI R0, 0
    B.NE bottom
    LDI R2, 1
bottom:
    CMPI R1, 92
    B.NE top
    LDI R3, -1
top:
    CMPI R1, 0
    B.NE paint
    LDI R3, 1
paint:
    LDI R6, 0xee
    CALL draw
    B.AL wait
; draw a two-byte-wide, four-row rectangle at x,y; R6 is packed color.
draw:
    MOV R4, R1
    LDI R5, 64
    MUL R4, R5
    ADD R4, R0
    ADDI R4, 0xc000
    LDI R5, 4
row:
    STB R6, [R4]
    STB R6, [R4 + 1]
    ADDI R4, 64
    DEC R5
    B.NE row
    RET

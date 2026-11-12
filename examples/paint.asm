; Arrows move one pixel per frame. A draws white; B erases; Start clears.
; Cursor is a reversible overlay: the packed byte below it is saved in RAM.
.entry start
start:
    LDI R0, 64
    LDI R1, 48
    LDI R7, 0xffff
    LDI R5, 0xcC20
    LDI R6, 0
    CALL cursor
wait:
    LDI R2, 0xd802
    LDW R3, [R2]
    CMP R3, R7
    B.EQ wait
    MOV R7, R3
; restore old cursor byte (which may include the last painted pixel)
    STB R6, [R5]
    LDI R2, 0xd800
    LDB R4, [R2]
    LDB R3, [R2 + 1]
    LDI R2, 64
    TEST R3, R2
    B.EQ move
    LDI R5, 0xc000
    LDI R6, 0
clear:
    STB R6, [R5]
    INC R5
    CMPI R5, 0xd800
    B.NE clear
move:
    LDI R2, 1
    TEST R4, R2
    B.EQ down
    CMPI R1, 0
    B.EQ down
    DEC R1
down:
    LDI R2, 2
    TEST R4, R2
    B.EQ left
    CMPI R1, 95
    B.EQ left
    INC R1
left:
    LDI R2, 4
    TEST R4, R2
    B.EQ right
    CMPI R0, 0
    B.EQ right
    DEC R0
right:
    LDI R2, 8
    TEST R4, R2
    B.EQ location
    CMPI R0, 127
    B.EQ location
    INC R0
location:
    MOV R5, R1
    LDI R2, 64
    MUL R5, R2
    MOV R3, R0
    LDI R2, 1
    SHR R3, R2
    ADD R5, R3
    ADDI R5, 0xc000
    LDB R6, [R5]
; build nibble mask R3 and preserve mask R2
    MOV R3, R0
    LDI R2, 1
    AND R3, R2
    LDI R2, 4
    MUL R3, R2
    LDI R2, 15
    SHL R2, R3
    MOV R3, R2
    NOT R2
; B has precedence over A, and preserves the neighbouring pixel
    PUSH R2
    LDI R2, 32
    TEST R4, R2
    POP R2
    B.NE erase
    PUSH R2
    LDI R2, 16
    TEST R4, R2
    POP R2
    B.EQ overlay
    OR R6, R3
    B.AL overlay
erase:
    AND R6, R2
overlay:
    CALL cursor
    JMP wait
cursor:
    MOV R3, R6
    LDI R2, 0x88
    XOR R3, R2
    STB R3, [R5]
    RET

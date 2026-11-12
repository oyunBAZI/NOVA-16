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
    SHL R5, R4
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
    HALT

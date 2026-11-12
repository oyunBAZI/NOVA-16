; ABI1 graphics. Scratch E0 palette index; all callee-saved regs preserved.
n16_color:
    LDI R1, 15
    AND R0, R1
    LDI R1, 0x00e0
    STW R0, [R1]
    RET
; pixel(x,y,index): R3 status 0/1; clip denied coordinates, preserve neighbour.
n16_pixel:
    PUSH R4
    PUSH R5
    PUSH R6
    CMPI R0, 128
    B.CS n16_pixel_bad
    CMPI R1, 96
    B.CS n16_pixel_bad
    MOV R4, R0
    LDI R3, 1
    AND R4, R3
    MOV R5, R1
    LDI R3, 64
    MUL R5, R3
    MOV R6, R0
    LDI R3, 1
    SHR R6, R3
    ADD R5, R6
    ADDI R5, 0xc000
    LDI R3, 15
    AND R2, R3
    LDB R6, [R5]
    CMPI R4, 0
    B.NE n16_pixel_high
    LDI R3, 0xf0
    AND R6, R3
    B.AL n16_pixel_store
n16_pixel_high:
    LDI R3, 15
    AND R6, R3
    LDI R3, 4
    SHL R2, R3
n16_pixel_store:
    OR R6, R2
    STB R6, [R5]
    LDI R3, 0
    B.AL n16_pixel_done
n16_pixel_bad:
    LDI R3, 1
n16_pixel_done:
    POP R6
    POP R5
    POP R4
    RET
; rect(x,y,width,height) uses selected color, clips right/bottom, no-op if empty.
n16_rect:
    PUSH R4
    PUSH R5
    PUSH R6
    CMPI R0, 128
    B.CS n16_rect_done
    CMPI R1, 96
    B.CS n16_rect_done
    CMPI R2, 0
    B.EQ n16_rect_done
    CMPI R3, 0
    B.EQ n16_rect_done
    LDI R4, 128
    SUB R4, R0
    CMP R2, R4
    B.LS n16_rect_width
    MOV R2, R4
n16_rect_width:
    LDI R4, 96
    SUB R4, R1
    CMP R3, R4
    B.LS n16_rect_height
    MOV R3, R4
n16_rect_height:
    MOV R4, R0
    MOV R5, R2
    MOV R6, R3
n16_rect_row:
    PUSH R5
    MOV R0, R4
n16_rect_column:
    LDI R2, 0x00e0
    LDB R2, [R2]
    CALL n16_pixel
    INC R0
    DEC R5
    B.NE n16_rect_column
    POP R5
    INC R1
    DEC R6
    B.NE n16_rect_row
n16_rect_done:
    LDI R3, 0
    POP R6
    POP R5
    POP R4
    RET
; clear(index) fills VRAM in <=12500 instructions, no host rendering.
n16_clear:
    PUSH R4
    LDI R1, 15
    AND R0, R1
    MOV R1, R0
    LDI R2, 4
    SHL R1, R2
    OR R0, R1
    MOV R1, R0
    LDI R2, 8
    SHL R1, R2
    OR R1, R0
    LDI R0, 0xc000
    LDI R4, 3072
n16_clear_loop:
    STW R1, [R0]
    ADDI R0, 2
    DEC R4
    B.NE n16_clear_loop
    POP R4
    RET
; palette(index,r,g,b) rejects invalid arguments before any RGB write.
n16_palette:
    PUSH R4
    CMPI R0, 16
    B.CS n16_palette_bad
    CMPI R1, 255
    B.HI n16_palette_bad
    CMPI R2, 255
    B.HI n16_palette_bad
    CMPI R3, 255
    B.HI n16_palette_bad
    LDI R4, 3
    MUL R0, R4
    ADDI R0, 0xd820
    STB R1, [R0]
    STB R2, [R0 + 1]
    STB R3, [R0 + 2]
    LDI R0, 0
    POP R4
    RET
n16_palette_bad:
    LDI R0, 1
    POP R4
    RET
; Opaque bitmap/sprite: x,y,source, packed(height<<8|width), one index byte/pixel.
; Source must be a valid contiguous RAM/VRAM/ROM range; full range preflighted.
n16_sprite:
n16_bitmap:
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    MOV R4, R0
    MOV R5, R3
    LDI R0, 255
    AND R5, R0
    MOV R6, R3
    LDI R0, 8
    SHR R6, R0
    CMPI R5, 0
    B.EQ n16_bitmap_ok
    CMPI R6, 0
    B.EQ n16_bitmap_ok
    CMPI R5, 128
    B.HI n16_bitmap_bad
    CMPI R6, 96
    B.HI n16_bitmap_bad
    MOV R0, R5
    MUL R0, R6
    CMPI R2, 0xe000
    B.CS n16_bitmap_rom
    MOV R3, R2
    ADD R3, R0
    B.CS n16_bitmap_bad
    CMPI R3, 0xd800
    B.HI n16_bitmap_bad
    B.AL n16_bitmap_ready
n16_bitmap_rom:
    MOV R3, R2
    NOT R3
    INC R3
    CMP R0, R3
    B.HI n16_bitmap_bad
n16_bitmap_ready:
    CMPI R4, 128
    B.CS n16_bitmap_ok
    CMPI R1, 96
    B.CS n16_bitmap_ok
    MOV R7, R2
n16_bitmap_row:
    PUSH R5
    MOV R0, R4
n16_bitmap_column:
    LDB R2, [R7]
    CALL n16_pixel
    INC R7
    INC R0
    DEC R5
    B.NE n16_bitmap_column
    POP R5
    INC R1
    DEC R6
    B.NE n16_bitmap_row
n16_bitmap_ok:
    LDI R3, 0
    B.AL n16_bitmap_done
n16_bitmap_bad:
    LDI R3, 1
n16_bitmap_done:
    POP R7
    POP R6
    POP R5
    POP R4
    RET

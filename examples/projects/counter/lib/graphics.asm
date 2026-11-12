initialize:
    LDI R0, result
    LDI R1, 42
    STW R1, [R0]
    RET
draw_result:
    LDI R0, framebuffer
    STB R1, [R0]
    RET

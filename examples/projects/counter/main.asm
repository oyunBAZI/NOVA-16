; One shared namespace; includes are expanded in textual order.
.include "lib/constants.asm"
.entry start
start:
    CALL initialize
    CALL sample_input
    CALL draw_result
    HALT
.include "lib/graphics.asm"
.include "lib/input.asm"

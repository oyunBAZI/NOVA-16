; State is inspectable by symbols; host never implements game rules.
.equ state, 0x0100
.equ mode, state
.equ paddle_x, state + 2
.equ ball_x, state + 4
.equ ball_y, state + 6
.equ velocity_x, state + 8
.equ velocity_y, state + 10
.equ lives, state + 12
.equ score, state + 14
.equ remaining, state + 16
.equ bricks, 0x0200

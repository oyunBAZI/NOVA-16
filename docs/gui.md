# SDL2 frontend
Build with `zig build -Dgui=true`. Install SDL2 development libraries first
(e.g. libsdl2-dev on Debian/Ubuntu). SDL2 is linked only into the GUI-enabled
nova16 executable. Core, assembler, debugger and tests do not depend on it.
SDL structures and constants are accessed only by sdl_adapter.c compiled against the installed SDL2 headers. Zig uses our own checked 8-byte input ABI.

`nova16 run ROM --gui --scale 4 --frames 100000 --max-instructions 1000000000`
uses nearest-neighbour RGB24 streaming textures. Scaling is an integer 1–32.
Default limits remain 120 presented frames and 10 million retired instructions.
Host pacing targets approximately 60 Hz; guest time remains instruction based.

Keys: arrows, Z=A, X=B, Enter=Start, Right Shift=Select.
Space pauses/resumes host execution, R resets/reloads, Escape exits.
HALT leaves the image visible until the presentation limit or quit.

Validated on Linux with SDL 2.32.4: actual 512×384 splash, ball motion at
multiple positions, Z+Right painted a visible stroke, Escape shutdown.
Dummy-driver smoke also completed three animation frames and generated PPM.
The session had SDL runtime but no development symlink: validation used a
local libSDL2.so symlink and `--search-prefix /tmp/nova-host`. Normal developer
installs use the system SDL2 development package instead.


## Adapter and automated graphical acceptance
`zig build gui-test -Dgui=true` opens a real SDL window, boots each guest, reads
back renderer output and compares every physical pixel to integer-scaled guest
RGB. It also verifies 640×512 letterboxing, every button mapping, key release,
focus-loss release, pause/reset/quit, window-close events and actual guest paint
input. Linux CI uses Xvfb; native Windows/macOS GUI jobs use their desktop runner.
`SDL_VIDEODRIVER=dummy` is useful locally when no display is attached.

The window is resizable/high-DPI aware; logical pixels stay 128×96 with nearest
integer scaling and black letterboxes. Frame pacing uses SDL performance counters
at 1/60 second; no host clock enters the machine core. Adapter failures report
SDL error text and clean up partial initialization. Header ABI assumptions are
checked by the C compiler; no SDL_Event byte offsets are handwritten in Zig.

A readback regression caught that SDL clips ReadPixels to the logical viewport.
The verifier now temporarily reads the complete physical target before restoring
logical sizing, so letterbox bytes are actually measured, not assumed zero.

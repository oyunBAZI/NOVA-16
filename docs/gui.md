# SDL2 frontend
Build with `zig build -Dgui=true`. Install SDL2 development libraries first
(e.g. libsdl2-dev on Debian/Ubuntu). SDL2 is linked only into the GUI-enabled
nova16 executable. Core, assembler, debugger and tests do not depend on it.
The frontend declares the small SDL2 C ABI directly, with no generated bindings.

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

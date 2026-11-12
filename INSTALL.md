# Installing an official binary package
Download the ZIP for your OS/CPU and its `.zip.sha256` from GitHub Releases.
Verify the ZIP with `sha256sum --check FILE.zip.sha256` on Linux,
`shasum -a 256 FILE.zip` on macOS, or `Get-FileHash FILE.zip -Algorithm SHA256`
in PowerShell and compare the published value. Extract the complete folder.

Packages include native ReleaseSafe headless binaries, all seven ROMs, typed compiler, guest libraries, complete
sources/tests, docs and MIT license. No Zig or SDL installation is needed to use them.
The optional graphical frontend is built from source with SDL2 development
libraries; these headless release binaries return an explanation for --gui.

From the extracted folder on Linux/macOS:

```
./bin/n16asm examples/boot_splash.asm --out splash.n16
./bin/nova16 inspect splash.n16
./bin/nova16 run splash.n16 --headless --frames 120 --screenshot splash.ppm --state-json splash.json
./bin/n16dbg splash.n16
```

On Windows use `.\bin\nova16.exe` (and the corresponding n16asm/n16dbg `.exe`)
with the same arguments. Use `help` inside the debugger, then `regs`, `step`,
`frame`, `input`, `trace`, `savesnap` and `loadsnap` as needed.

On macOS the binaries are unsigned. Follow your organization's policy for
unsigned open-source CLI tools or build from source; code signing is not claimed.
The platform matrix and compatibility policy are in docs/platforms.md and
CONTRIBUTING.md. RC versions are prereleases, not a stability guarantee.

To build the included multi-file game from an extracted package:

```sh
./bin/n16asm examples/projects/breakout/main.asm --out game.n16 --debug-symbols game.sym2
./bin/nova16 inspect game.n16 --json
./bin/n16dbg game.n16 --symbols game.sym2
```

Inside the debugger use `input 64`, `frame 1`, `input 0`, `frame 5`,
`mem score 2`, `break game.asm:49`, `continue`. Headless replays need no SDL.
Python helpers in scripts/ accept explicit `--emulator bin/nova16` or
`--assembler bin/n16asm`; use `.exe` on Windows. For source-build examples in
the developer guide, replace `zig-out/bin/` with `bin/` in an extracted package
and create the output directory `zig-out` once.

When a release includes provenance.sigstore.json, verify an archive using
`gh attestation verify FILE.zip --repo oyunBAZI/NOVA-16 --bundle provenance.sigstore.json`.
This verifies workflow provenance; it does not provide macOS notarization or
Windows Authenticode signing. Publication is blocked if CI provenance verification
fails. Older releases without a bundle make no attestation claim.

For typed/assembly projects, Python3.10+ is optional orchestration:

```sh
python3 scripts/n16.py new my-project
python3 scripts/n16.py test my-project
python3 scripts/n16.py debug my-project
python3 scripts/n16.py pack my-project --out my-project.zip
```

The helper automatically finds extracted bin/ tools. Portable verified projects
are also in applications/crates.zip and applications/pixel_studio.zip. Extract
one and use the same test/debug workflow. Full source/test build inputs are
included for rebuilding the SDK with Zig0.17.1; Zig is not needed to compile
guest applications using the native n16c/n16asm binaries. See docs/apps/README.md.

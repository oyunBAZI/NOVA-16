# Installing an official binary package
Download the ZIP for your OS/CPU and its `.zip.sha256` from GitHub Releases.
Verify the ZIP with `sha256sum --check FILE.zip.sha256` on Linux,
`shasum -a 256 FILE.zip` on macOS, or `Get-FileHash FILE.zip -Algorithm SHA256`
in PowerShell and compare the published value. Extract the complete folder.

Packages include native ReleaseSafe headless binaries, all ROMs and assembly
sources, docs and MIT license. No Zig or SDL installation is needed to use them.
The optional graphical frontend is built from source with SDL2 development
libraries; these headless release binaries return an explanation for --gui.

From the extracted folder on Linux/macOS:

```
./bin/n16asm examples/boot_splash.asm --out splash.n16
./bin/nova16 inspect splash.n16
./bin/nova16 run splash.n16 --headless --frames 120 --screenshot splash.ppm --state-json splash.json
./bin/n16dbg splash.n16
```

On Windows use `\.\bin\nova16.exe` (and the corresponding n16asm/n16dbg `.exe`)
with the same arguments. Use `help` inside the debugger, then `regs`, `step`,
`frame`, `input`, `trace`, `savesnap` and `loadsnap` as needed.

On macOS the binaries are unsigned. Follow your organization's policy for
unsigned open-source CLI tools or build from source; code signing is not claimed.
The platform matrix and compatibility policy are in docs/platforms.md and
CONTRIBUTING.md. RC versions are prereleases, not a stability guarantee.

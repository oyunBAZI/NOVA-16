# NOVA Workbench

The optional Workbench integrates the existing native VM, typed compiler and
debugger in a local browser interface. It requires Python 3.10+ and a current
browser. No Python/JavaScript packages or network downloads are needed at runtime.

## Start

From a source checkout with Zig 0.17.1:

```sh
zig build -Doptimize=ReleaseSafe
python3 scripts/workbench.py
```

An extracted SDK already contains the native tools, demos, sources and frontend:
run `python3 scripts/workbench.py` in its top-level directory, without Zig.
On Windows use `python` if that is your Python executable. The launcher opens a
browser and prints the exact local session URL. `--no-browser` suppresses opening;
`--port 8765` selects a fixed port. By default the OS chooses an available port.
Keep the process running; Ctrl+C closes it and its VM child.

## Workflow

- Choose a verified guest ROM and **Load ROM**, then **Run** or **Frame**. Run is
  host-paced, with a target of 60 guest frames/sec subject to machine/transport
  overhead. The core uses deterministic instruction/slot timing, never wall time.
- The editor is a separate single-file N16C scratch program. **Build & load**
  invokes the real compiler with source maps and size accounting. Only a valid
  build and candidate VM replace the running machine. A diagnostic leaves the
  previous ROM and machine intact. **Save source** and **ROM** export your work.
  Last submitted source stays in the launcher session; unsubmitted edits stay in
  the tab. Export source to keep it after closing.
- **Step** executes one instruction, **Next line** uses real source mappings,
  **Frame** completes a logical frame unless a debugger breakpoint/watchpoint
  intervenes. Use Step to move beyond a current breakpoint or BRK. Run stops on
  breaks, watchpoints, guest HALT/BRK, traps and failed operations. F5 toggles Run;
  F10 steps. A host Pause stops requesting work; it does not fabricate guest BRK.
- Add a breakpoint with `0xe000`, a symbol, or `main.n16c:8`. Remove it with its
  chip. The console also supports `vars`, `source`, `watch 0xc000`, `unwatch`,
  `trace 16`, `input 16`, `regs`, and other read/step commands. Commands are
  bounded to 20,000 transitions; file commands are deliberately unavailable.
- **Reverse** undoes one recorded instruction/input action or one whole Frame
  action. Capacity defaults to 32 entries (at most 32 full machine copies).
  Instruction trace retains 128 transitions. Frame grouping avoids a whole-machine
  copy at every instruction, while retaining per-instruction breakpoint/watch
  checks. This is bounded exact history, not a delta-history implementation.
- Focus/click the framebuffer for arrows, Z/A, X/B, Enter/Start and Shift/Select.
  Onscreen controls also work. Releasing focus releases keyboard input; backgrounding
  pauses host execution. Controller bits/pressed-edge state come from the VM.
- Inspect a 256-byte memory window from `0x0000` through `0xff00`. `??` means
  denied, not zero. Reads never acknowledge input/vblank latches. The ROM and
  MMIO cannot be edited through this view. Hover pixels for VRAM address/nibble.
- **Save snapshot** downloads canonical N16S1/N16S2 bytes. Restore checks version,
  ROM identity, CRCs and complete state before commit, and clears stale history
  and playback data only on success. Corrupt or other-ROM states are rejected.
- **Input replay** resets and runs 1–120 canonical frames with increasing
  `frame mask` lines. Blank/comment lines are allowed; masks may be decimal or
  hexadecimal and persist until the next event. Replay intentionally ignores
  debugger break/watch stops, retaining those settings for later debugging.
- Profile 2 exposes actual voices, clocks, timer/IRQ state and PCM. **Enable sound**
  queues that integer PCM in the browser after your click; it synthesizes no notes.
  Host buffering is capped to 150 ms, and Pause/rewind/reload clears queued sound.
  **Export last frame WAV** downloads the currently displayed complete or partial
  PCM frame as 48 kHz mono PCM16. Profile 1 shows no imaginary audio hardware.

Loading a ROM does not replace the independent editor buffer with a different
program. Source locations from that ROM are labelled as compiled-ROM locations;
only your successfully built, unmodified buffer is eligible for editor line marks.

## Local service boundary

The server binds only IPv4 loopback. Requests require a per-launch random bearer
token, exact Host, and same-origin Origin when present. The token is passed in
the launch URL fragment, then kept in the tab's session storage. No cookies,
CORS grants, directory listings, generic path endpoints or remote file uploads
are provided. Static files use a fixed allowlist, a restrictive CSP and no-store.
Stale session revisions are rejected so another tab cannot silently apply stale
commands. Builds occur in an owned temporary directory, never a caller path.

Do not put this local development service behind a public proxy. It is not a
multi-user hosted IDE. Native compiler code still processes input source; process
timeouts and bounds provide failure containment, not an operating-system sandbox.

## JSON-lines protocol version 1

`n16bridge ROM [--symbols MAP]` starts one real machine. Send one JSON object per
line and read one JSON object per response. It emits no banner or prompts. EOF
ends successfully. All parse/output allocations have a per-request lifetime.
No operation takes a filesystem path. Invalid/oversized lines yield errors and
drain through their newline, allowing the next request to proceed.

```json
{"version":1,"op":"observe","address":49152,"length":256}
{"version":1,"op":"command","command":"step"}
{"version":1,"op":"command","command":"break main.n16c:8"}
{"version":1,"op":"frame"}
{"version":1,"op":"replay_frame"}
{"version":1,"op":"snapshot"}
{"version":1,"op":"restore","data":"4e313653..."}
```

`replay_frame` uses canonical `Machine.frame`/`frameAudio` without debugger stops.
It is for deterministic automation; ordinary `frame` honors debugger stops.
Snapshots are lower-case hex strings of the existing canonical snapshot bytes.
Unknown request fields/versions/operations are rejected. Memory length is 0–256;
address + length must fit 64 KiB. Line capacity is `2 * 67680 + 4096` bytes.
Commands are allowlisted and 256 bytes maximum. Snapshot restore is at most
67,680 decoded bytes. The HTTP layer caps JSON at 200,000 bytes and source at
64 KiB. Child operations have 10-second (VM) / 15-second (compiler) budgets.

Responses contain `version`, `ok`, `error`, `output`, the unchanged profile-specific
`state` object, `profile`, `stopped`, history counts, packed `vram` hex, `palette`,
`display_enabled`, source location, breakpoint addresses, bounded memory bytes
(`null` for denied addresses), disassembly, input latches, and optional audio.
Profile 1 `audio` is null. Profile 2 PCM is the actual last completed Frame or
current partial-frame prefix, with an explicit `completed_frame` flag. Reverse,
restore and instruction-command execution invalidate previous frame PCM.
Parse/oversize errors may omit observation. Large 64-bit counters are JSON
numbers; browser presentation loses integer precision beyond JavaScript's exact
integer range, while native state/snapshots retain their full precision.

## Verification

```sh
zig build fmt
zig build test --summary all --test-timeout 2m
zig build test -Doptimize=ReleaseSafe --summary all --test-timeout 2m
python3 scripts/workbench_acceptance.py
```

Workbench acceptance compares all nine demos' CPU state and framebuffer bytes
against the native runner; V2's last 800 PCM samples must also match its WAV.
It tests rewind/re-execution, corrupt-state atomicity, real compiler output,
failed-build retention, candidate-before-replace, deterministic scheduled replay,
nonacknowledging MMIO reads, limits, line resynchronization and HTTP boundaries.
CI runs this suite on Linux, Windows and macOS in Debug and ReleaseSafe, and
again from extracted native SDK packages. These are execution/HTTP tests;
browser layout, accessibility and actual sound-device testing remain separate.


## Platform evolution additions

The editor can explicitly select V1/V2 and size/baseline code generation.
**Open source** copies a typed demo into the editor after confirming replacement;
loading a ROM alone still leaves edits independent. Bootstrap distinguishes the
editor text (`editor_source`) from the VM's current source-location record.
The demo list adds NOVA Tracker and Starfall; their controls are documented in
[evolution applications](evolution/applications.md).

Native Workbench history now defaults to the bounded 2048-entry delta mode.
`history delta 4096`, `history 32` and `history 0` select deeper delta, original
complete-state, or disabled history. Retention also depends on journal pressure.

The optional [offline export](wasm.md) runs this same interface against a dedicated
Wasm Worker. It embeds all assets/cartridges and denies network connections.
Source/ROM/snapshot downloads and guest PCM remain generated from the real core.
The native HTTP token/origin policy applies to the Python service; it is not an
authentication layer for an independent offline tab.

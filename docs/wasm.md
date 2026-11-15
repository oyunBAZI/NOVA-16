# Portable Wasm runtime and offline Workbench

The normal build now installs `zig-out/wasm/nova16.wasm`. It contains the same
CPU, devices, snapshots, debugger and typed compiler as the native tools. It has
no WebAssembly imports: no host filesystem, clocks, entropy, audio callback or
network service is part of guest execution. V1/V2 selection still comes from
the explicit ROM version. The module's linear memory has a 64 MiB maximum;
that limit does not describe a browser or Node process's total memory use.

## Offline Workbench export

```sh
zig build -Doptimize=ReleaseSafe
python3 scripts/package_web.py
```

This creates `zig-out/web/NOVA16-Offline-Workbench.html`. The SDK includes the
same export under `web/`. It bundles the Wasm binary, shared Workbench interface,
all eleven cartridges and their maps, and editable sources for the four typed
applications. Its VM/compiler run in a dedicated Worker. The export contains no
external script or stylesheet; its CSP denies network connections. Browser sound
uses actual guest PCM after the user's audio-enable gesture.

Open the file in a modern browser supporting WebAssembly and Blob Workers.
The native local Workbench remains available through `python scripts/workbench.py`.
The offline model has the same build, revision, replay, snapshot and debugger
operations; each tab owns an independent VM. Neither frontend persists unsaved
source after the tab/session is closed. Use **Save source**, **ROM** and snapshots
for work you want to keep. Opening an example source asks before replacing edits.

The engineering report distinguishes Node-executed runtime/Worker-model checks
from rendered-browser checks. A browser's file-origin, CSP, Worker and audio-device
behavior is a separate acceptance gate; the managed browser in the development
environment rejected local-file navigation and could not reach container loopback.
No rendered-browser pass or stable GUI release is claimed by the Node tests.

## JavaScript embedding

`wasm/nova16.mjs` works in browsers and Node without packages:

```js
import {createMachine} from './wasm/nova16.mjs';
const machine = await createMachine(wasmBytes); // Uint8Array or WebAssembly.Module
machine.load(romBytes);
const frame = machine.request({op: 'frame'});
console.log(frame.state, frame.vram, frame.audio?.pcm);
const saved = machine.request({op: 'snapshot'}).snapshot;
machine.request({op: 'restore', data: saved});
const built = machine.compile('fn main()->u16{return 42;}', {profile: 2});
machine.dispose();
```

Use a Worker for an interactive UI. Calls are synchronous and one instance must
not receive overlapping writes to its input scratch buffer. Instantiate separate
modules for separate machines. The adapter refreshes memory views after every
call, because `memory.grow` detaches old JavaScript views. `setSymbols(text)` owns
both JSON map data and legacy symbol names across subsequent buffer reuse.

Compiler defaults are size optimization and explicit profile 1. Pass `profile:2`
for V2 or `optimize:false` for the earlier code generation. Failed validation and
compilation retain the running machine. A successful compile installs its checked
map and returns the exact native ROM bytes and size report. `version` is the core
version, while the embedding ABI and JSON protocol have independent version 1.

## Low-level embedding ABI 1

| Export | Contract |
|---|---|
|`n16_abi_version()`|Embedding ABI, currently 1|
|`n16_version_ptr/length()`|UTF-8 core version in linear memory|
|`n16_input_ptr/capacity()`|Reusable 1 MiB input buffer|
|`n16_output_ptr/length()`|Reusable response buffer, at most 512,000 bytes|
|`n16_load(length)`|Read at most 8,224 ROM bytes from input; validate before replacement|
|`n16_request(length)`|Process bounded protocol-v1 JSON using the shared native serializer|
|`n16_set_symbols(length)`|Read a checked JSON or legacy map, at most 1 MiB|
|`n16_compile(length,profile,optimize)`|At most 65,536 UTF-8 source bytes; profile 1/2, optimization 0/1|
|`n16_dispose()`|Release maps/history and clear the selected machine; the instance can be reused|

Response JSON's `ok` field is authoritative for application operations. The
function result reports whether the wrapper produced an ordinary response;
a protocol response can still contain `ok:false`. Read output before another
operation overwrites it. Native protocol request and instruction budgets remain
in force, including 20,000 transitions per command. The buffer's larger capacity
supports maps, not larger JSON VM requests. Portable snapshots remain byte-identical.

```sh
node scripts/wasm_acceptance.mjs
python3 scripts/package_web.py
node scripts/offline_acceptance.mjs
node scripts/offline_worker_acceptance.mjs
```

The first check executes the actual Wasm module and compares native state,
framebuffer, integer PCM, snapshots, restore/reverse, compiler ROM bytes and symbol
lifetimes across all demos. It also exercises 100 compile/restore replacements,
independent instances and memory-growth limits. The second checks the complete
export's scripts/assets and runs its Worker model through builds, replay, stale
revisions and rejected operations. It does not substitute for browser rendering.

The Worker acceptance test executes the export's exact launcher and generated
Worker source in a real Node thread. It verifies startup, concurrent-message
revision rejection, typed V2 compilation, execution and failed-build retention.
It supplies Node equivalents for Blob/Worker messaging and does not test a
browser's URL/CSP policy, DOM layout or audio device.


Shared protocol responses are serialized within 500,000 bytes; command text is
bounded to 65,536 bytes. Oversized valid inspections return `OutputLimit` without
publishing a partial JSON line or terminating the VM. Both native and Wasm tests
exercise a 3,000-symbol listing and a 600,000-byte source-location field, then
verify state retention and successful subsequent commands.

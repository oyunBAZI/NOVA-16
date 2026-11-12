# Performance methodology and baseline

```
zig build bench -Doptimize=ReleaseSafe -- --samples 5 --instructions 2000000
python3 scripts/benchmark.py --out zig-out/benchmark.json
```

The first command runs the native host benchmark; the second installs it, runs
it separately from the compiler and records JSON, hardware/OS/compiler/mode,
source commit/dirty state, executable SHA256, individual samples and medians.
POSIX wait4 measures this child's peak RSS (KiB); Windows currently reports null
rather than inventing a memory measurement. Timers use the host monotonic clock,
never guest state. All sample counts and instruction budgets are bounded.

CPU workload is real assembled LDI/ADD/JMP code, with expected register and
retirement checks. Frame workload uses the same loop through Machine.frame.
Other batches measure initialization/reset (10000 each), ROM validation/load
(1000), real splash assembly (100), bus word pairs (100000), and packed-to-RGB
conversion (1000). Perturbations/compiler barriers prevent dead-code removal.
Assembler results use an allocator that really frees memory between iterations.
Five medians reduce warmup/noise; no CPU affinity or exclusive host is claimed.

Initial local component profile, Zig 0.17.1 ReleaseSafe (`safe`), native
emeraldrapids target on Intel Xeon Platinum 8573C, Linux x86_64 / glibc 2.41:

| Component | Median |
|---|---:|
|CPU instruction|51.40 ns|
|20,000-instruction headless frame|1.019 ms|
|Initialize|2.267 μs|
|Reset|2.695 μs|
|Load small benchmark ROM|2.447 μs|
|Assemble complete splash|1.079 ms|
|Bus word write/read pair|36.09 ns|
|Convert full RGB framebuffer|13.277 μs|
|Isolated benchmark peak RSS|13,312 KiB|

This is a component timing profile, not a sampling flame graph. Assembly is the
most costly one-shot component measured; emulation time is dominated by guest
execution rather than RGB conversion in this workload. No speculative dispatch
optimization was applied. The host has no perf executable; that limitation is
explicit. Use a sampling profiler on a representative ROM before optimizing an
individual function. Results are not cross-hardware performance guarantees.

CI publishes per-commit performance-baseline JSON. Compare like hardware,
optimization, workload, samples and environment; review large changes rather
than failing portable correctness gates on a noisy shared-runner threshold.
Release evaluation retains the raw baseline artifact so regressions remain visible.

The full second five-sample measurement is retained in
[benchmarks/linux-initial.json](benchmarks/linux-initial.json), including raw
samples, hardware, source tree and the corresponding public commit. Differences
from the first timing table illustrate normal shared-host variance.

## v0.3 measurements
Raw reports: benchmarks/v0.3-linux.json and v0.2-same-host.json. Both measured
on the same AMD EPYC 9V74 / znver4 host, Zig 0.17.1 ReleaseSafe, three samples.
Do not compare these numerically with the older Intel-host baseline.

| Operation | v0.2 same host | v0.3 |
|---|---:|---:|
| Instruction | 38.90 ns | 38.12 ns |
| Headless frame | 0.796 ms | 0.757 ms |
| Splash assembly | 529.3 µs | 32.5 µs |
| RGB conversion | 12.48 µs | 13.18 µs |
| Peak process RSS | 13,312 KiB | 13,312 KiB |

CPU/frame/RGB differences are small and not claimed as optimizations. Indexed
symbol/source lookup explains the substantial assembly improvement; the separate
Debug reverse-chain before/after measurement is in v0.3-ledger.md. New workloads:
4,097-symbol assembly 3.753 ms, debugger command stepping 97.4 ns/instruction,
snapshot encode 167.3 µs/restore 154.2 µs, real Breakout frame 0.763 ms. All
workloads validate real machine results; timers stay in host tooling. These are
component wall-time measurements, not a sampling profiler or universal speed
promise. Source fingerprint/dirty state, CPU and raw samples are preserved.

## v0.4 developer workloads

Raw: [benchmarks/v0.4-linux.json](benchmarks/v0.4-linux.json), public source
cb350a2cbeeb2666a188d4680eac4aed00beff6f, clean measured source. Zig0.17.1
ReleaseSafe/znver4, AMD EPYC9V74, three samples,2M instructions each, same CPU
and base workload settings as v0.3. Component medians:

| Operation | v0.4 |
|---|---:|
|Instruction|39.38ns|
|Headless frame|0.791ms|
|Splash assembly|36.88µs|
|4097-symbol assembly|3.998ms|
|Debugger command step|101.13ns|
|Full history step|1.707µs|
|32-entry exact history storage|2,101,248bytes|
|Candidate capture-only lower bound|50.34ns|
|Snapshot encode/restore|176.45/163.33µs|
|Crates compilation|6.350ms|
|Pixel Studio compilation|7.257ms|
|Crates/Pixel Studio frame|0.949/0.927ms|
|RGB full-frame conversion|14.84µs|
|Isolated benchmark peak RSS|57,704KiB|

Core CPU/frame timings are modestly higher than v0.3 (38.12ns/0.757ms), without
an algorithm change to V1 execution. No speedup is claimed; shared-host timing
variance and expanded process working set limit causal interpretation. The
benchmark now retains two compiler contexts (16MiB private capacity each) and
measures compiler/runtime workloads, so its RSS is intentionally not comparable
to the former13,312KiB core-only benchmark as an emulator memory regression.
History candidate excludes delta extraction/restore/checkpoint costs; it is not
an implemented alternative or an end-to-end speed claim. See projects.md for
the measured decision to retain opt-in bounded exact copies.

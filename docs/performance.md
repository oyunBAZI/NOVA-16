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

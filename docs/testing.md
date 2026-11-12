# Verification and fuzzing
Tests are grouped by subsystem next to the implementation. `conformance_tests`
checks every first word, all legal round trips and execution edge cases;
`sequence_tests` compares stateful mixed streams with an independent model;
`integration_tests` boots real assembly ROMs and checks deterministic pixels.
`core/snapshot`, `debug/debugger`, `asm/assembler`, `debug/symbols`, device and
ROM tests exercise their own negative cases. `scripts/acceptance.py` drives only
distributed CLIs, including IDE diagnostics, source maps and snapshot persistence.

```
zig build test --test-timeout 2m
python3 scripts/acceptance.py
zig build test -Doptimize=ReleaseSafe --fuzz=1K --test-timeout 5m
zig build test -Doptimize=ReleaseSafe --fuzz=100K --test-timeout 10m
```

The deterministic malformed-input smoke runs 1000 cases across seven target
families in normal CI. Smith's guided target covers ROM containers, assembly,
expressions/directives, debugger commands, input schedules, raw instruction
streams and CRC-correct snapshot mutations. Inputs are at most 256 bytes;
guest streams are capped at 64 instructions, snapshot probes at 32, debugger
commands at 4096 bytes, history at 32 states, and host formats at explicit limits.
Allocation-failure tests check result ownership, not only parser error paths.

Zig 0.17.1's default x86 debug backend produced a zero-PC corrupted coverage
file in this environment. ReleaseSafe/LLVM succeeded: the initial 1K smoke
performed 1179 runs, 174 unique runs, and reached 841/15441 instrumented PCs
(5.45%). These are fuzzer feedback PCs across its instrumented binary, not a
source-line coverage percentage or a claim of completeness. Keep `.zig-cache`
to retain the corpus/feedback. The scheduled workflow runs 100K iterations weekly.
Separate kcov source coverage is published by CI; inspect missed lines and add
regression cases rather than optimizing tests merely to increase percentages.

Regression policy: every confirmed defect gets an executable reproducer;
never update golden hashes just to make CI green. Timeouts/fuzzer crashes fail
CI. Seeds and bounded counts are fixed/reported so failures can be reproduced.

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

| Suite | Main coverage |
|---|---|
|arch/isa + debug/disasm|All 65536 first words and all legal round trips|
|core/cpu + conformance_tests|Flags, control flow, stack, permissions and faults|
|sequence_tests|32×300 independent mixed-state comparisons, RAM self-modification|
|core/bus + devices|Region/MMIO boundaries, latches, packed pixels/palette|
|rom/format|Header/payload corruption, length/entry/CRC rejection|
|asm/assembler + debug/symbols|Spans, constants, listings, schemas/ROM identity|
|debug/debugger + core/snapshot|Frame/input, trace/undo, complete restore/atomicity|
|integration_tests|All ROM boots, original golden outputs and input replay|
|fuzz_tests|Guided/deterministic malformed inputs and allocation-failure paths|
|scripts/acceptance + verify_package|Real CLIs and extracted native distributions|
|frontend/selfTest|Actual SDL events, controls, resize and all-pixel readback|

The N16S byte protocol also has an independently encoded struct/zlib SHA256
vector in snapshots.md, asserted on every native OS/backend. Code-coverage and
performance artifacts remain diagnostics with explicit methods and limitations.
Source coverage is measured on the linked unit/integration test binary; unused
CLI entrypoints and the separate C/SDL frontend are not included in that binary's
line totals. Their executable behavior is verified by black-box/native graphical
acceptance. The coverage report is not presented as a whole-product percentage.

v0.3 regression gates: `python3 scripts/developer_acceptance.py`,
`python3 scripts/game_acceptance.py`, and Linux
`python3 scripts/project_stress.py`. Reliability records live in
`docs/reliability/`; CI retains guided corpus inputs and source-coverage output.
Included-file success/error ownership is tested with every allocation failing in
turn; snapshots cover every trap encoding and CRC-correct invalid state metadata.
Full Breakout winning/losing input paths execute guest instructions, and snapshot
replay compares complete CPU/memory state. Feedback PC coverage is distinct from
kcov's linked-test source line coverage; neither includes unlinked host CLIs.

v0.4 adds ABI1/guest-library real-ROM tests, >=25 executable positive/negative
compiler cases, an independent192-program seeded interpreter/CPU campaign,
allocation/depth/layout failures and map3 variable validation. Native CI runs:

```
python scripts/compatibility_acceptance.py
python scripts/compiler_acceptance.py
python scripts/project_acceptance.py
python scripts/application_acceptance.py
python scripts/v2_contract_vectors.py
```

Both optimization modes run all of these, plus original developer/game suites.
SDK extraction repeats typed project/debug/application checks without Zig, with
nested verified application packages rebuilt using extracted n16c. Ten guided
families now include compiler source and legacy/map2/map3 parsing. The independent
V2 fixture/model checks validate specification math and V1 rejection only.

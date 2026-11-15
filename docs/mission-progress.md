# NOVA-16 mission checkpoint — 2026-11-12

## Source and integration

Main inspected at `a25afb5d72dbd0d0a2afd27409c84d112ccb35d0`.
PR #5 remains open at `beccc7a7a4f59892eeed59ed9cdf80ec719db76d`.
Work is isolated on `feat/compact-guest-linking`, based on that PR head.
No merge, branch deletion or release publication is authorized by this checkpoint.
The direct git CLI has no GitHub credentials. Initial connector calls selected
the wrong account link; selecting the repository owner connection restored
authenticated admin/push access. Publish the isolated branch through that
connection, preserving the tested source tree and PR-5 parent.

PR #5 fresh API state: open, unmerged, mergeable=true, mergeable_state=unstable.
Latest full run `43253107116` shows 14 successful substantive checks and skipped
release. Run `43253088961` also has a cancelled macOS SDL check at the same head.
This mixed history does not establish the cause of the unstable label. Required
branch policy/review-thread resolution was not authenticated. Reviews API was
empty. Do not bypass policy or infer permission to merge.

## Phase checklist

- [x] Inspect source heads and independent local main/PR-5 baselines.
- [x] Reuse existing V2 hardware; inspect canonical scheduler, device write
  candidates, IRQ mask semantics and snapshot validation against revision2.
- [x] Main Debug 94/94; PR-5 Debug and ReleaseSafe 116/116.
- [x] Reproduce Crates/Pixel Studio sizes before changes.
- [x] Phase 1A: typed call reachability, library symbol graph, size reports,
  retained-variable/source debugging, reproducible CLI artifacts.
- [x] Full/compact guest ABI fixtures execute on the real CPU with register,
  retirement, RAM, framebuffer, palette and input comparisons.
- [x] Final Debug and ReleaseSafe 119/119; compatibility/CLI/project/application/
  V2/contract/security/game gates and 100 seeded project adversaries pass.
- [ ] Phase -1 integration: authenticated required-check/policy reconciliation,
  complete review, supported merge workflow, post-merge CI.
- [ ] Phase 0: remaining exhaustive forensic/platform matrix and baseline metrics.
- [ ] Phase 1B: instruction-level compact codegen, broader optimizer oracle
  campaign, enhanced ROM-overflow diagnostics. No instruction rewrites shipped.
- [ ] Phases 2–5: existing V2 is reused and regressed, not newly claimed complete
  across every requested hardening/reverse-history gate.
- [ ] Phase 6 Workbench; phase 7 Tracker/Starfall; phase 8 modules/SDK evolution;
  phase 9 monitor/proposal; phase 10 release gates. Not implemented here.

## Implemented

`src/compiler/guest_linker.zig` builds a bounded label-block graph using the real
assembler parser/operand grammar. It follows exact symbol references, calls,
branches, fallthrough and address-taken font data in the reviewed position-
independent ABI1 library. It rejects indirect control flow or unsupported layout
rather than assuming safety. The shared assembly files are unchanged.

`src/compiler/compiler.zig` computes typed function reachability from main,
including recursive cycles, still checks unused bodies, omits removed function
locals from maps, and emits deterministic byte accounting. Scaffolding remains
conservative. No ISA, ABI, ROM envelope, snapshot, device or runtime changes.

`src/cli/compiler_main.zig` publishes `--size-report PATH` through the same
atomic-output staging and source/duplicate alias checks as other artifacts.
Tests cover transitive/recursive calls, shared tails/data, unsupported library
forms, unused diagnostics, maps, report accounting/determinism and failed output
preflight. Library tests compare compact linking with the unmodified full library.

## Measured results

| Program | Before payload | After payload | Saved |
|---|---:|---:|---:|
| Minimal return-42 | 1,812 | 92 | 1,720 (94.92%) |
| Crates | 7,944 | 7,100 | 844 (10.62%) |
| Pixel Studio | 5,010 | 4,222 | 788 (15.73%) |

All ten application framebuffer hashes and expected RAM outcomes are unchanged.
All five original V1 ROM byte identities match. Compiler-generated ROM checksums
change intentionally because unreachable bytes are removed; new maps match them.

Warm-filesystem, alternating fresh-process Debug compiler samples on the same
host are in `docs/benchmarks/compact-linking-linux.json`. Median before/after:
minimal 19.27/15.60 ms, Crates 32.05/38.76 ms, Pixel Studio 26.06/27.86 ms.
These small samples include startup and output publication; they show a compile-
time cost for the larger apps, not a universal speed improvement. Execution
instruction sequences/counts are unchanged for retained guest library fixtures.

## Validation and limits

Pinned Zig 0.17.1, Linux x86_64. Exact captured commands/results are represented by
`docs/reliability/compact-linking-local.json` and the exported checkpoint logs.
Ran build, fmt, Debug/ReleaseSafe tests, v2-model-test, acceptance.py,
compatibility_acceptance.py, developer_acceptance.py, compiler_acceptance.py,
project_acceptance.py, application_acceptance.py, v2_acceptance.py,
v2_contract_vectors.py, security_check.py, game_acceptance.py, project_stress.py.
All passed. No golden hashes were changed.

SDL setup downloaded and checksum-verified the pinned source but stopped before
configuration because CMake is missing. No local SDL GUI, new Windows/macOS
native run, new coverage result or expanded fuzz campaign is claimed. SDK package
checks, if executed after the source commit, are captured in the exported logs;
this document does not predeclare their result. No stable release is claimed.

Next executable step: publish this branch for review atop PR #5 through the
verified owner connection, then reconcile the required integration checks. Continue Phase
1B with identifying fixtures and real-CPU oracle comparisons before changing
instruction generation; then the Workbench vertical slice. Keep Profile 2 fixed.

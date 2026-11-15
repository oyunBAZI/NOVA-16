# Integration review notes

These are source-review notes for the requested integration, not a declaration
that a PR has already merged. Final GitHub merge results and the tested heads
are recorded in the PR conversation after integration.

| PR | Reviewed change | Main risk and evidence |
|---|---|---|
|1|Checkout 7.0.1, immutable SHA `3d3c42e`|Major action runtime/default change; hosted runner execution, credentials remain disabled, ordinary PR trigger retained|
|2|Upload-artifact 7.0.2, immutable SHA `cf430e0`|Cross-job artifact compatibility; all three native SDK uploads and a real download/manifest verification job|
|3|Download-artifact 8.0.2, immutable SHA `9000827`|Release download path was otherwise skipped in ordinary CI; new ordinary job uses the same pattern/merge inputs and checks all three SDKs|
|4|Setup-python 7.1.0, immutable SHA `6d4fd22`|Node/runtime and Python provisioning changes; exact upgrade tested in the full new Linux/Windows/macOS workflow|
|5|Explicit V2 sound/IRQ/snapshot profile|Read candidate MMIO writes, stack preflight, shared slot scheduler and validate-before-assign restore; independent contract/PCM vectors, unchanged V1 goldens, native matrices|
|6|Reachable typed functions and ABI1 library linking|Reviewed parsed-symbol/fallthrough handling, unsupported indirect flow rejection and diagnostics for unused bodies; compact/full parity and original app fixtures|
|7|Native Workbench and frame-group history|Reviewed candidate-before-replace, bounded JSON/HTTP, token/origin, maps and ownership; exact frame/snapshot/PCM parity; later shared BRK resume and input/cleanup fixes are in PR 9|
|8|Optimizer, packed graphics, delta history and Wasm|Reviewed side-effect preservation, byte/nibble boundaries, full small-state capture plus pre-write journal, owned maps, import-free embedding and Worker isolation; independent compiler campaign, whole-state/delta comparisons, app goldens and exported Worker execution|
|9|Workbench reliability and complete integration|Actual app event tests, real native/offline Chromium, bounded lifecycle/drafts/imports, exact paused-state rewind, buffered framing, two stateful soaks, failure-reporting tests and all upgraded Actions exercised together|

## Findings resolved in PR 9

- A guest BRK was cleared before history captured the original paused state.
  Resume and its first transition now share one undo boundary. Both profiles,
  full/delta modes, zero budgets, existing embedding groups and 2,000 seeded
  action sequences check canonical rewind and re-execution.
- The source overlay inherited gutter width/alignment. Gutter and code layout
  are independent; large valid source uses at most one highlighted gutter span.
  Real browser geometry and scrolling are checked, rather than inferred from DOM
  structure tests.
- Controller owners were conflated, and indicators used stale local held bits.
  Keys/pointers retain independent ownership; indicators use actual guest state.
- Repeated observations could enqueue an already completed PCM frame again.
  Playback deduplicates actual device-frame identity and closes failed audio
  activation candidates. No host synthesizer was introduced.
- Native and offline replay accepted different schedules and reported requested
  rather than actual completed frames. Both hosts execute one shared acceptance
  corpus before mutation and report actual completion.
- Offline errors could strand pending requests. Constructor, fatal/decode,
  timeout, clone, queue and page-lifecycle paths now settle work explicitly.
- Broken native child cleanup could mask its original failure with a second
  buffered-stdin error. Rejected cartridge candidates now preserve the live VM
  and cleanup is safe even after a pipe failure.
- The native CLI transports issued one OS read per input byte. Buffered input
  preserves exact framing, cap/oversize draining and final unterminated requests.
- Validation previously left ambiguous evidence on timeouts or source changes.
  Checkpoints are atomic; failed launches/timeouts are recorded and changing
  source invalidates otherwise successful gates.
- PR commits previously launched the entire matrix twice, for branch push and
  PR synchronization. CI now runs on PRs, main pushes and manual dispatch;
  release/main validation and the separate scheduled fuzz workflow remain.

## Integration policy

All original PR heads have been inspected and their existing checks reviewed;
the original eight had no review submissions or inline comments at the initial
inspection. Recheck open PRs, review threads, head SHAs and mergeability at the
end of the requested work period. Merge with ordinary merge commits so stacked
and Dependabot commits remain ancestors of main. Preserve unique unmerged work.

The quality branch includes the four dependency heads as parents and normalizes
their pins in newer workflow jobs. Its final tested source tree therefore also
represents the proposed combined main tree. Main merges are deferred until the
requested engineering/testing period finishes. No release publication, branch
protection bypass, signing or notarization is part of this integration.

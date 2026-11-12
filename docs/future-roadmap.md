# Prioritized maintenance roadmap

## Implemented engineering baseline (0.2.0-rc.1)
Host/target-correct builds; native Linux/Windows/macOS and graphical gates;
independent execution comparisons; true diagnostics/source maps/listings; frame
investigation, trace/undo and snapshots; bounded malformed-input/guided fuzzing;
coverage artifacts; component baselines; checksum-bearing native packages and
verification-gated prereleases. ISA V1/N16R/State JSON V1 remain compatible.

## V1.1 priorities
1. Accumulate longer scheduled fuzz evidence and convert every failure to a
   regression; review source coverage misses and allocation behavior.
2. Profile adversarial large constant graphs and source-span lookup costs; add
   measured parser work budgets or indexed locations if justified. Current source
   size is bounded but not every host parsing operation has a separate work cap.
3. Add embedding accessors that discourage inconsistent public host-state mutation
   while retaining source compatibility; document migration before restricting APIs.
4. Expand native OS/CPU coverage where actual runners are available. Cross-built
   macOS x86_64 is not promoted to native-tested merely because it compiles.
5. Improve multi-error/caret diagnostics and richer editor integration without
   changing valid V1 code generation or the legacy symbol reader.
6. Evaluate signing, cryptographic artifact attestations, installers and administrator-
   approved branch rules. Current RC packages are unsigned, with SHA256 manifests.
7. Compare performance on like hardware and representative real ROMs; profile
   individual hot functions before applying dispatch or parser optimizations.

## V2, only after compatibility design and approval
Versioned interrupts/peripherals, optional audio, richer guest tools and a higher-
level guest language can be explored independently. No audio, filesystem,
networking, hardware compatibility or multitasking capability is currently claimed.
Every architectural extension needs explicit ISA/device/ROM versioning and tests;
V1 ROM semantics must remain available. Complexity is not itself a roadmap goal.

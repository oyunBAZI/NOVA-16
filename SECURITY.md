# Security policy
NOVA-16 runs a fictional ISA, never native ROM code. It validates ROMs, snapshots,
source widths and execution budgets. The core has no host filesystem/network API.
CRC32 detects accidental corruption; it is not authentication. SHA256 release
manifests identify exact files; acquire packages from the official repository.
No program should assume unknown ROMs or source files are trusted data.

Report reproducible host crashes, bounds errors or unintended filesystem access
through GitHub private vulnerability reporting if enabled, or contact the owner
through the repository before publicly disclosing sensitive details. Do not
include credentials or unrelated personal information. No private reporting
service or response SLA is implied. RC builds receive best-effort fixes.

CI permissions default to read-only. Only gated release publication can write
release contents; external actions and toolchains are pinned. Source coverage and
fuzzing are diagnostics, not proofs of safety. Workflow dependency updates are
reviewed and tested. Administrators may require native/cross/GUI/reliability/
security checks in branch rules; this task does not silently enable repository
administration settings or bypass protections.

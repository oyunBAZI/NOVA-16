# Contributing and compatibility
Pin Zig 0.17.1. Run formatting, native build/tests, Python acceptance and the
ReleaseSafe fuzz smoke before submitting changes. Add a regression for each
confirmed defect. Preserve ISA V1/N16R binary compatibility, deterministic timing,
and State JSON schema 1. Version snapshot/debug formats independently.

```
zig build fmt
zig build
zig build test --test-timeout 2m
python3 scripts/acceptance.py
zig build test -Doptimize=ReleaseSafe --fuzz=1K --test-timeout 5m
```

Use a feature branch and PR with concrete behavior, compatibility impact and
executed validation. New features require tests. Never remove assertions or
change golden images solely to obtain green results. A source listing, snapshot
or symbol-map change must document its schema/version. Native host tools must
remain separate from selected-target binaries. Graphical code stays outside core.

Compatibility policy: existing N16R v1 ROMs and ISA encodings stay valid; source
changes improving invalid-input diagnostics may introduce more specific error
codes. New formats reject unknown versions. Legacy symbol maps remain readable,
with their lack of identity checking documented. Stable release promotion needs
all native execution, graphical, reliability and distributable gates green.

# Release and maintenance procedure

Native Debug and ReleaseSafe execution, cross-build ROM identity, all three SDL
renderer/input tests, benchmark, guided fuzz, source coverage, workflow policy
checks and native extracted-package verification gate publication in one CI DAG.
Jobs have finite time limits; failure never becomes an optional release gate.
External actions are SHA-pinned and Zig archive hashes are committed. Dependabot
proposes action updates; maintainers review compatibility before merging.

Build native distributables using baseline CPU features:

```
zig build -Doptimize=ReleaseSafe -Dstrip=true -Dcpu=baseline
python3 scripts/package.py
python3 scripts/verify_package.py dist/nova16-VERSION-OS-ARCH.zip
```

Archives contain three headless tools, all ROMs/symbols and assembly sources,
manuals, installation guide and licenses. Every file has a manifest SHA256;
the ZIP has its own `.zip.sha256`. Manifest records the source commit, dirty
state and executable-reported compiler/OS/architecture/CPU/optimization/GUI info.
Archive order, timestamps and permissions are normalized. Repackaging identical
artifacts at one commit yields identical bytes. Native binaries are built with
stripped debug info and baseline CPU features; binary reproducibility still
depends on the pinned toolchain/target/OS environment, recorded by build info.
No reproducibility across different compilers or operating systems is implied.

Before publishing: update build.zig.zon/src/version.zig consistently, changelog,
platform evidence and installation instructions. A reviewed main-branch commit
beginning `Release:` triggers the release job only after every verification
job succeeds. It publishes `vVERSION` as a prerelease with assets targeting the
exact tested commit. Existing release tags are never overwritten. Native CI
also publishes package artifacts for ordinary commits without creating releases.

Only the publication job has contents:write; other jobs default to read-only
and checkout does not persist credentials. Manifests and GitHub source targeting
provide traceability; cryptographic build attestations and code signing are not
configured. Repository rulesets were not changed. Administrators may require
CI jobs in branch protection; no protection bypass is part of this workflow.
Promoting an RC to stable requires explicit review of the complete evidence and
known limitations, not merely changing the label.

# Platform evidence

| Platform | Native Debug/ReleaseSafe | Native SDL renderer/input | Cross-build from Linux |
|---|---|---|---|
|Linux x86_64, Ubuntu 24.04 CI|Passed|Passed under Xvfb|Passed|
|Windows x86_64, Server 2022 CI|Passed|Passed on native desktop|Passed|
|macOS 15 aarch64|Passed|Passed on native desktop|x86_64 + aarch64 passed|

Native v0.3 headless/graphical/package gate evidence: CI run 43168396493
at release commit 1316575f4789ebe6c566d655b4237a837e89b916. It executes actual
binaries and all component, golden ROM, replay, snapshot and CLI checks.
Native macOS package extraction has passed for aarch64. Architecture-specific release filenames and executable build info identify the
actual native runner architecture; cross-compiling the other macOS architecture
is not presented as native execution of that architecture. Other OS versions,
CPUs and SDL backends are unverified. No universal macOS binary is claimed.

Release packaging/native extraction checks are additional gates introduced in
0.2.0-rc.1. Official published binaries are baseline-CPU ReleaseSafe headless
builds with no SDL dependency; optional graphical source builds need platform
SDL2 development libraries. macOS signing/notarization and installers are not
provided. See INSTALL.md and releasing.md for the exact artifact contract.

## Developer-platform candidate verification
0.3 candidate CI 43165008976 passed Linux/macOS ReleaseSafe extracted project/
game/debugger checks, cross builds, all three native SDL gates (including genuine
SDL2 on macOS), benchmarks, fuzzing and source coverage. Windows passed its
build/core/original-ROM checks and caught a CRLF diagnostic defect in the new
acceptance; the corrected code is in the final Release checkpoint. Do not infer
that the candidate's failed Windows job passed. The published 0.3 release's
Verification link must show all native jobs green before 0.3 support is claimed.


## v0.3 native closure — passed
Final release CI 43168396493 passed every native Debug/ReleaseSafe job, all
three actual SDL input/renderer jobs, cross-builds, extracted packages, benchmark,
guided fuzzing, source coverage, policy and provenance verification. The earlier
Windows CRLF failure above is fixed and its regression passed on Windows.
The separate arithmetic model passed 3 tests per native mode; core suite passed
72. All three native packages were published with checksums and Sigstore bundle.
The release remains an unsigned OS-binary prerelease; V2 hardware is not shipped.

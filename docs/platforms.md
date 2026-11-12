# Platform evidence

| Platform | Native Debug/ReleaseSafe | Native SDL renderer/input | Cross-build from Linux |
|---|---|---|---|
|Linux x86_64, Ubuntu 24.04 CI|Passed|Passed under Xvfb|Passed|
|Windows x86_64, Server 2022 CI|Passed|Passed on native desktop|Passed|
|macOS 15 native CI architecture|Passed|Passed on native desktop|x86_64 + aarch64 passed|

Native headless/graphical gate evidence: CI run 43140210006. It executes actual
binaries and all component, golden ROM, replay, snapshot and CLI checks.
Architecture-specific release filenames and executable build info identify the
actual native runner architecture; cross-compiling the other macOS architecture
is not presented as native execution of that architecture. Other OS versions,
CPUs and SDL backends are unverified. No universal macOS binary is claimed.

Release packaging/native extraction checks are additional gates introduced in
0.2.0-rc.1. Official published binaries are baseline-CPU ReleaseSafe headless
builds with no SDL dependency; optional graphical source builds need platform
SDL2 development libraries. macOS signing/notarization and installers are not
provided. See INSTALL.md and releasing.md for the exact artifact contract.

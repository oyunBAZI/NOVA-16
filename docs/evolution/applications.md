# V2 applications

These are ordinary typed guest programs built by `n16c --architecture nova16-v2`.
Their rendering, controls, collisions, sequence state and sound-device writes run
on the emulated CPU. Their project manifests explicitly select profile 2. The
same binaries run headlessly, through SDL, in the native Workbench or in Wasm.
The optional frontends do not synthesize game rules or musical notes.

## NOVA Tracker

Four voices each have sixteen steps. Each cell holds a rest or one of twelve
chromatic C4–B4 pitches. The selected cell has white borders; the marker above
the grid shows the current playback step. The upper values are ticks per step,
selected note and selected waveform. The lower-right value counts edits.

| Controller | Action |
|---|---|
|Arrows|Select a step/voice, wrapping within the grid|
|A / Z|Cycle rest → twelve pitches → rest|
|B / X|Clear the selected cell|
|Start / Enter|Pause/resume playback|
|Select / Shift + Up/Down|Decrease/increase ticks per step, bounded 2–30|
|Select / Shift + Left/Right|Previous/next waveform for the selected voice|

Waveforms 0–3 are square, saw, triangle and deterministic noise. Each note writes
both phase-step halves while its voice is disabled, then enables/resets it.
Playback polls the V2 20,000-slot reloading timer; it never consults host time.
The default eight ticks per sixteenth-note step correspond to a nominal 112.5
BPM when the guest services each 60 Hz timer event. Long guest operations can
coalesce pending timer events, so this is a small chip sequencer, not an external
clock synchronization promise. It currently edits one 64-cell pattern. Use an
exact snapshot to preserve that pattern and playback state.

## Starfall

A complete small arcade loop has a title screen, three six-enemy waves, four
simultaneous bullets, three lives, score, pause, win/loss screens and restart.
The fixed formation makes input replays reproducible. A triangle-wave bass line
and short square/noise effects use the actual V2 sound device.

| Controller | Action |
|---|---|
|Start / Enter on title/end screen|Start/restart|
|Left/Right|Move the ship|
|Hold A / Z|Fire with a guest-controlled cooldown|
|Start / Enter during play|Pause/resume; pause silences active voices|

Destroying an enemy awards ten points. Clearing three waves wins at 180 points.
Escaping enemies consume lives, with a short invulnerability interval. Zero lives
ends the game. The recorded win input completes with two lives; independent loss,
pause/resume and restart schedules are also committed.

## Reproduction

```sh
python3 scripts/n16.py test examples/projects/nova_tracker
python3 scripts/n16.py test examples/projects/starfall
python3 scripts/evolution_acceptance.py
```

The ten scene fixtures in `scenes.json` pin PPM hashes and guest RAM outcomes.
Acceptance compares canonical native execution with bridge replay, including
last-frame PCM, edited note/wave arrays, pause silence and restart. Long runs
supply an explicit instruction budget; a default CLI budget must not accidentally
prevent late replay events from executing. Native project tests now derive that
budget from their requested frame count. Existing Crates, Pixel Studio and all
five original V1 ROM identities keep their separate unchanged regression gates.

"""Assemble original Breakout files and verify actual CPU-generated replay images."""
import hashlib
import json
import pathlib
import subprocess
import tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = ROOT/'zig-out/bin'
with tempfile.TemporaryDirectory() as directory:
    temp = pathlib.Path(directory)
    rom = temp/'breakout.n16'
    subprocess.run([str(BIN/'n16asm'), str(ROOT/'examples/projects/breakout/main.asm'), '--out', str(rom)], check=True, timeout=30)
    assert rom.read_bytes() == (ROOT/'zig-out/demos/breakout.n16').read_bytes()
    assert len(rom.read_bytes()) <= 8224
    hashes = json.loads((ROOT/'docs/gameplay/hashes.json').read_text())
    for scene, frames, schedule in [('title',5,None), ('play',120,'play-input.txt'), ('win',1000,'win-input.txt'), ('loss',1000,'right-input.txt')]:
        shot = temp/(scene+'.ppm')
        cmd = [str(BIN/'nova16'), 'run', str(rom), '--headless', '--frames', str(frames),
               '--max-instructions', '20000000', '--screenshot', str(shot)]
        if schedule:
            cmd += ['--input', str(ROOT/'docs/gameplay'/schedule)]
        result = subprocess.run(cmd, check=True, text=True, capture_output=True, timeout=60)
        assert not json.loads(result.stdout)['trapped']
        assert hashlib.sha256(shot.read_bytes()).hexdigest() == hashes[scene], scene
        print(scene+': real guest replay/framebuffer SHA256 OK')

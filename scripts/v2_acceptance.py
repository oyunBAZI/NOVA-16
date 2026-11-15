"""Black-box V2 guest execution, real PCM/graphics, source debugging and snapshots."""
import base64
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import wave
import zlib

ROOT = Path(__file__).resolve().parents[1]
BINS = ROOT/('zig-out/bin' if (ROOT/'zig-out/bin').exists() else 'bin')
DEMOS = ROOT/('zig-out/demos' if (ROOT/'zig-out/demos').exists() else 'demos')

def run(name, *args, stdin=None, ok=True):
    p = subprocess.run([str(BINS/(name+('.exe' if os.name == 'nt' else ''))), *map(str, args)],
                       input=stdin, capture_output=True, text=True, timeout=60)
    if ok:
        assert p.returncode == 0, (name, p.stdout, p.stderr)
    else:
        assert p.returncode != 0, (name, p.stdout, p.stderr)
    return p

def snapshot(data):
    assert len(data) == 67680
    assert struct.unpack_from('<4sHHIIHHI8s', data) == (b'N16S', 2, 0, 67680, zlib.crc32(data[32:]), 2, 4, 32, b'\0'*8)
    for i, (tag, offset, size) in enumerate([(b'CPU2',112,160),(b'MEM1',272,65584),(b'AUD1',65856,1696),(b'IRQ1',67552,128)]):
        assert struct.unpack_from('<4sIIII', data, 32+i*20) == (tag, offset, size, zlib.crc32(data[offset:offset+size]), 0)
    return data

def main():
    fixtures = json.loads((ROOT/'docs/vectors/v2-contract.json').read_text())
    evidence = {}
    with tempfile.TemporaryDirectory(prefix='nova-v2-') as temporary:
        temp = Path(temporary)
        fixture_rom = temp/'fixture.n16'
        fixture_rom.write_bytes(base64.b64decode(fixtures['rom2_halt']['base64']))
        info = json.loads(run('nova16', 'inspect', fixture_rom, '--json').stdout)
        assert info['rom_version'] == info['isa_version'] == 2
        # Idle frames after HALT still clock timers and generate complete PCM.
        silent = temp/'silent.wav'
        halted = json.loads(run('nova16', 'run', fixture_rom, '--frames', 2, '--wav', silent).stdout)
        assert halted['executed_instructions'] == 1 and halted['transition_slots'] == 40000 and halted['audio_samples'] == 1600
        with wave.open(str(silent)) as audio:
            assert audio.getparams()[:4] == (1, 2, 48000, 1600)
            assert not any(audio.readframes(1600))
        for name in ('nova_sound', 'interrupt_canvas'):
            source = ROOT/'examples/projects'/name
            assert (source/'lib/v2.asm').read_bytes() == (ROOT/'guest/v2.asm').read_bytes()
            generated = temp/(name+'.n16')
            symbols = temp/(name+'.map.json')
            run('n16asm', source/'main.asm', '--architecture', 'nova16-v2', '--out', generated, '--debug-symbols', symbols)
            assert generated.read_bytes() == (DEMOS/(name+'.n16')).read_bytes()
            run('n16asm', source/'main.asm', '--out', temp/'denied.n16', ok=False)
            states = []
            digests = []
            for index in range(2):
                wav = temp/f'{name}-{index}.wav'
                ppm = temp/f'{name}-{index}.ppm'
                state = json.loads(run('nova16', 'run', generated, '--frames', 180, '--max-instructions', 4000000,
                                       '--wav', wav, '--screenshot', ppm).stdout)
                assert state['schema_version'] == 2 and state['machine_profile'] == 2
                assert state['transition_slots'] == 3600000 and state['audio_samples'] == 144000
                assert state['executed_instructions'] + state['irq_entries'] == state['transition_slots']
                assert not state['trapped'] and not state['halted']
                assert state['irq_entries'] >= (179 if name == 'interrupt_canvas' else 23)
                with wave.open(str(wav)) as audio:
                    assert audio.getparams()[:4] == (1, 2, 48000, 144000)
                    pcm = audio.readframes(144000)
                    values = struct.unpack('<144000h', pcm)
                    assert min(values) < -1000 and max(values) > 1000 and len(set(values)) > 100
                states.append(state)
                digests.append(dict(wav_sha256=hashlib.sha256(wav.read_bytes()).hexdigest(),
                                    pcm_sha256=hashlib.sha256(pcm).hexdigest(),
                                    ppm_sha256=hashlib.sha256(ppm.read_bytes()).hexdigest()))
            assert states[0] == states[1] and digests[0] == digests[1]
            saved, again = temp/'saved.n16s', temp/'again.n16s'
            session = run('n16dbg', generated, '--symbols', symbols, stdin=(
                f'history 32\nbreak timer_handler\ncontinue 200000\ndevices\ntrace 4\n'
                f'savesnap {saved}\nstep\nreverse\nsavesnap {again}\nloadsnap {saved}\nregs\nquit\n')).stdout
            assert 'error:' not in session and 'breakpoint before' in session and 'IRQ1 entry' in session and 'profile=2' in session
            assert snapshot(saved.read_bytes()) == snapshot(again.read_bytes())
            evidence[name] = dict(frames=180, rom_payload_bytes=len(generated.read_bytes())-32, state=states[0], **digests[0])
            print(f'{name}: guest voices/timer/IRQs, deterministic PCM/PPM, source breakpoint and exact reverse/snapshot passed')
        # Independent persistent-state vectors accepted only under explicit ROM2.
        for key in ('snapshot2_idle137', 'snapshot2_boundary20000'):
            path, encoded = temp/(key+'.n16s'), temp/'encoded.n16s'
            path.write_bytes(base64.b64decode(fixtures[key]['base64']))
            session = run('n16dbg', fixture_rom, stdin=f'loadsnap {path}\nsavesnap {encoded}\nquit\n').stdout
            assert 'error:' not in session and snapshot(path.read_bytes()) == encoded.read_bytes()
            denied = run('n16dbg', DEMOS/'diagnostics.n16', stdin=f'step 2\nregs\nloadsnap {path}\nregs\nquit\n').stdout
            assert 'SnapshotProfile' in denied
            import re
            pcs = re.findall(r'PC=.* SP=.*', denied)
            assert len(pcs) == 2 and pcs[0] == pcs[1]
        reference = ROOT/'docs/reliability/v2-demonstrations.json'
        if '--record' in sys.argv:
            reference.write_text(json.dumps(evidence, indent=2, sort_keys=True)+'\n')
        else:
            assert json.loads(reference.read_text()) == evidence, 'V2 demo replay drift'
    print('V2 black-box acceptance passed; complete original V1 gates remain separate')

if __name__ == '__main__':
    main()

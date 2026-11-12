"""Run a versioned deterministic guest test using installed NOVA-16 tools."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import tempfile

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('spec', type=pathlib.Path)
    ap.add_argument('--emulator', default='zig-out/bin/nova16')
    args = ap.parse_args()
    spec = json.loads(args.spec.read_text())
    allowed = {'schema_version', 'rom', 'frames', 'input', 'registers', 'ppm_sha256', 'halted'}
    if set(spec)-allowed or spec.get('schema_version') != 1:
        raise ValueError('unsupported guest test schema')
    frames = spec.get('frames', 120)
    if type(frames) is not int or not 0 <= frames <= 10000:
        raise ValueError('invalid frame limit')
    root = args.spec.resolve().parent
    with tempfile.TemporaryDirectory() as directory:
        shot = pathlib.Path(directory)/'output.ppm'
        cmd = [args.emulator, 'run', str(root/spec['rom']), '--headless', '--frames', str(frames), '--screenshot', str(shot)]
        if 'input' in spec:
            cmd += ['--input', str(root/spec['input'])]
        result = subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=60)
        state = json.loads(result.stdout)
        if state['trapped']:
            raise AssertionError(state)
        for index, value in spec.get('registers', {}).items():
            assert state['registers'][int(index)] == value, state
        if 'halted' in spec:
            assert state['halted'] == spec['halted'], state
        digest = hashlib.sha256(shot.read_bytes()).hexdigest()
        if 'ppm_sha256' in spec:
            assert digest == spec['ppm_sha256'], digest
        print(json.dumps({'schema_version': 1, 'passed': True, 'ppm_sha256': digest, 'state': state}, sort_keys=True))
if __name__ == '__main__':
    main()

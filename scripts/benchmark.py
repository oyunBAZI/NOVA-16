"""Collect repeatable component baselines and isolated process peak RSS on Linux."""
import argparse
import json
from pathlib import Path
import platform
import statistics
import hashlib
import os
import tempfile
import time
import subprocess
import sys

p = argparse.ArgumentParser()
p.add_argument('--out', default='zig-out/benchmark.json')
p.add_argument('--samples', type=int, default=5)
p.add_argument('--instructions', type=int, default=2_000_000)
args = p.parse_args()
subprocess.run(['zig', 'build', 'bench-build', '-Doptimize=ReleaseSafe'], check=True)
binary = Path('zig-out/bin/n16bench' + ('.exe' if sys.platform == 'win32' else '')).resolve()
command = [str(binary), '--samples', str(args.samples), '--instructions', str(args.instructions)]
peak_rss = None
if hasattr(os, 'wait4'):
    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(command, stdout=output, stderr=errors)
        deadline = time.monotonic() + 180
        while True:
            pid, status, usage = os.wait4(process.pid, os.WNOHANG)
            if pid:
                process.returncode = os.waitstatus_to_exitcode(status)
                break
            if time.monotonic() > deadline:
                process.kill(); os.wait4(process.pid, 0)
                process.returncode = -9
                raise TimeoutError('benchmark exceeded 180 seconds')
            time.sleep(0.005)
        output.seek(0); errors.seek(0)
        stdout, stderr = output.read().decode(), errors.read().decode()
        if process.returncode:
            raise RuntimeError(stderr)
        peak_rss = usage.ru_maxrss / (1024 if sys.platform == 'darwin' else 1)
else:
    run = subprocess.run(command, check=True, capture_output=True, text=True, timeout=180)
    stdout = run.stdout

data = json.loads(stdout)
data['host'] = platform.platform()
data['hardware_cpu'] = platform.processor()
if sys.platform.startswith('linux'):
    data['hardware_cpu'] = next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')), data['hardware_cpu'])
data['commit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
data['source_dirty'] = subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--', 'src', 'build.zig', 'examples']).returncode != 0
data['binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
data['peak_rss_kib'] = peak_rss
for sample in data['samples']:
    assert sample['operations'] > 0 and sample['nanoseconds'] > 0
assert {sample['name'] for sample in data['samples']} == {'cpu_instruction', 'headless_frame', 'initialize', 'reset', 'rom_load', 'assemble_splash', 'bus_word_pair', 'video_rgb_frame'}
groups = {}
for sample in data['samples']:
    groups.setdefault(sample['name'], []).append(sample['nanoseconds'] / sample['operations'])
data['median_ns_per_operation'] = {name: statistics.median(values) for name, values in groups.items()}
Path(args.out).parent.mkdir(parents=True, exist_ok=True)
Path(args.out).write_text(json.dumps(data, indent=2) + '\n')
for name, value in data['median_ns_per_operation'].items():
    print(f'{name}: {value:.2f} ns/operation')
print('peak RSS KiB:', data['peak_rss_kib'])

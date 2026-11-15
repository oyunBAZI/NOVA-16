"""Alternating same-host native restore round trips; no guest CPU speed claim."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


class Peer:
    def __init__(self, executable, rom):
        self.process = subprocess.Popen([str(executable), str(rom)], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.timer = threading.Timer(60, self.process.kill)
        self.timer.daemon = True
        self.timer.start()

    def exchange(self, data):
        self.process.stdin.write(data)
        self.process.stdin.flush()
        line = self.process.stdout.readline(512001)
        if len(line) > 512000 or not line.endswith(b'\n'):
            raise RuntimeError('Native peer returned invalid framing or exceeded its lifetime')
        result = json.loads(line)
        if not result.get('ok'):
            raise RuntimeError(result.get('error'))
        return result

    def close(self):
        self.timer.cancel()
        if self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=5)
        for stream in (self.process.stdin, self.process.stdout):
            try:
                stream.close()
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--samples', type=int, default=9)
    parser.add_argument('--out', type=Path, default=ROOT / 'zig-out/transport-benchmark.json')
    args = parser.parse_args()
    if not 3 <= args.samples <= 100:
        parser.error('--samples must be 3–100')
    programs = {'before': args.before.resolve(), 'after': args.after.resolve()}
    rom = ROOT / 'zig-out/demos/nova_sound.n16'
    peers = {}
    report = {'schema_version': 1, 'passed': False, 'samples': args.samples,
              'workload': 'V2 snapshot restore, pre-encoded request, full native JSON round trip',
              'limits': 'Same-host wall-clock samples under concurrent load; not guest CPU performance or an OS-wide guarantee',
              'rom_sha256': hashlib.sha256(rom.read_bytes()).hexdigest(),
              'binaries': {name: {'sha256': hashlib.sha256(program.read_bytes()).hexdigest(), 'bytes': program.stat().st_size}
                           for name, program in programs.items()},
              'restore_ns': {'before': [], 'after': []}, 'observe_ns': {'before': [], 'after': []}}
    try:
        for name, program in programs.items():
            peer = peers[name] = Peer(program, rom)
            peer.exchange(b'{"op":"command","command":"step 80"}\n')
            saved = peer.exchange(b'{"op":"snapshot"}\n')
            if name == 'before':
                snapshot, state = saved['snapshot'], saved['state']
            else:
                assert saved['snapshot'] == snapshot and saved['state'] == state
        request = (json.dumps({'op': 'restore', 'data': snapshot}, separators=(',', ':')) + '\n').encode()
        report['restore_request_bytes'] = len(request)
        for peer in peers.values():
            for _ in range(3):
                assert peer.exchange(request)['state'] == state
        for index in range(args.samples):
            for name in ('before', 'after') if index % 2 == 0 else ('after', 'before'):
                peer = peers[name]
                start = time.perf_counter_ns()
                restored = peer.exchange(request)
                report['restore_ns'][name].append(time.perf_counter_ns() - start)
                assert restored['state'] == state
                start = time.perf_counter_ns()
                peer.exchange(b'{}\n')
                report['observe_ns'][name].append(time.perf_counter_ns() - start)
                assert peer.exchange(b'{"op":"snapshot"}\n')['snapshot'] == snapshot
        report['median_restore_ns'] = {name: statistics.median(samples) for name, samples in report['restore_ns'].items()}
        report['median_observe_ns'] = {name: statistics.median(samples) for name, samples in report['observe_ns'].items()}
        report['passed'] = True
    except Exception as error:
        report['failure'] = str(error)
        raise
    finally:
        for peer in peers.values():
            peer.close()
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()

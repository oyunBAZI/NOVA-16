"""Local Workbench for the native NOVA-16 VM. Python 3.10+, no dependencies.

Run: python scripts/workbench.py [--port 0] [--no-browser]
The VM is n16bridge; this module handles presentation, isolated builds and HTTP.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import queue
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = ROOT / ('zig-out/bin' if (ROOT / 'zig-out/bin').is_dir() else 'bin')
DEMOS = ROOT / ('zig-out/demos' if (ROOT / 'zig-out/demos').is_dir() else 'demos')
ASSETS = ROOT / 'workbench'
MAX_BODY = 200_000
DEMO_NAMES = {
    'boot_splash': 'Boot sequence', 'bouncing_pixel': 'Bouncing pixel',
    'paint': 'Paint', 'diagnostics': 'Diagnostics', 'breakout': 'Breakout',
    'crates': 'Crates', 'pixel_studio': 'Pixel Studio',
    'nova_sound': 'NOVA Sound · V2', 'interrupt_canvas': 'Interrupt Canvas · V2',
}


def executable(name):
    return str(BIN / (name + ('.exe' if sys.platform == 'win32' else '')))


class Bridge:
    """Exactly one outstanding request; finite output and lifetime on failure."""
    def __init__(self, rom, symbols=None):
        args = [executable('n16bridge'), str(rom)]
        if symbols:
            args += ['--symbols', str(symbols)]
        self.process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL)
        self.responses = queue.Queue(maxsize=2)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            self.initial = self.request({'op': 'observe'})
        except Exception:
            self.close()
            raise

    def _read(self):
        try:
            while True:
                line = self.process.stdout.readline(512_001)
                if not line:
                    self.responses.put(None)
                    return
                if len(line) > 512_000 or not line.endswith(b'\n'):
                    self.responses.put(None)
                    return
                self.responses.put(json.loads(line))
        except (ValueError, OSError):
            self.responses.put(None)

    def request(self, payload):
        try:
            data = json.dumps(payload, separators=(',', ':')).encode() + b'\n'
            if len(data) > MAX_BODY:
                raise ValueError('Request too large')
            self.process.stdin.write(data)
            self.process.stdin.flush()
            result = self.responses.get(timeout=10)
            if result is None:
                raise RuntimeError('VM bridge exited; load a demo or build to restart it')
            return result
        except (BrokenPipeError, OSError, queue.Empty, RuntimeError) as error:
            self.close()
            raise RuntimeError('VM bridge stopped or exceeded its 10-second budget') from error

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=2)
        for stream in (self.process.stdin, self.process.stdout):
            if stream:
                stream.close()
        if threading.current_thread() is not self.reader:
            self.reader.join(timeout=2)


class Workbench:
    def __init__(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='nova16-workbench-')
        self.directory = pathlib.Path(self.temporary.name)
        self.bridge = None
        self.revision = 0
        self.title = ''
        self.generation = 0
        self.build_directory = None
        self.source = (ROOT / 'examples/typed/demo.n16c').read_text(encoding='utf-8')
        try:
            self.load_demo('boot_splash')
        except Exception:
            self.temporary.cleanup()
            raise

    def replace(self, rom, symbols, title):
        # Validate a candidate bridge before disposing of the working machine.
        candidate = Bridge(rom, symbols)
        previous = self.bridge
        self.bridge = candidate
        self.title = title
        if previous:
            previous.close()
        return candidate.initial

    def load_demo(self, name):
        if name not in DEMO_NAMES:
            raise ValueError('Unknown demo')
        rom = DEMOS / (name + '.n16')
        symbols = next((p for p in (DEMOS / (name + '.map.json'), DEMOS / (name + '.sym2'),
                                    DEMOS / (name + '.sym')) if p.is_file()), None)
        return self.replace(rom, symbols, DEMO_NAMES[name])

    def dispatch(self, request):
        if not isinstance(request, dict):
            raise ValueError('Request must be an object')
        op = request.get('op')
        if op != 'bootstrap' and (type(request.get('revision')) is not int or
                                  request['revision'] != self.revision):
            return 409, {'error': 'Session changed; refresh before continuing', 'revision': self.revision}
        if op == 'bootstrap':
            result = self.bridge.request({'op': 'observe'})
            result.update(source=self.source, demos=DEMO_NAMES)
        elif op == 'load':
            result = self.load_demo(request.get('demo'))
            self.revision += 1
        elif op == 'build':
            source = request.get('source')
            if not isinstance(source, str) or len(source.encode('utf-8')) > 65_536:
                raise ValueError('Source must be text, at most 64 KiB')
            self.source = source
            self.generation += 1
            directory = self.directory / str(self.generation)
            directory.mkdir()
            path = directory / 'main.n16c'
            path.write_text(source, encoding='utf-8')
            rom, symbols = directory / 'program.n16', directory / 'program.map.json'
            try:
                process = subprocess.run([executable('n16c'), str(path), '--out', str(rom),
                                          '--debug-symbols', str(symbols), '--size-report', str(directory / 'size.json'),
                                          '--diagnostics', 'json'], capture_output=True, timeout=15)
                if process.returncode:
                    result = self.bridge.request({'op': 'observe'})
                    result.update(ok=False, error='Build failed; previous machine retained',
                                  diagnostics=process.stderr.decode('utf-8', errors='replace')[:16_384])
                else:
                    result = self.replace(rom, symbols, 'main.n16c')
                    result.update(size_report=json.loads((directory / 'size.json').read_text()),
                                  rom=rom.read_bytes().hex())
                    old = self.build_directory
                    self.build_directory = directory
                    if old:
                        shutil.rmtree(old)
            finally:
                if directory != self.build_directory:
                    shutil.rmtree(directory)
            self.revision += 1
        elif op == 'vm':
            payload = request.get('request')
            if not isinstance(payload, dict):
                raise ValueError('Missing VM request')
            result = self.bridge.request(payload)
            self.revision += 1
        elif op == 'replay':
            text, frames = request.get('schedule'), request.get('frames')
            if not isinstance(text, str) or len(text) > 8192 or type(frames) is not int or not 1 <= frames <= 120:
                raise ValueError('Replay needs 1–120 frames and a schedule of at most 8 KiB')
            events = {}
            previous = -1
            for line in text.splitlines():
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                words = line.split()
                if len(words) != 2:
                    raise ValueError('Schedule lines are: frame mask')
                # Decimal and 0x hexadecimal, matching the native schedule format.
                frame, bits = (int(word, 16 if word.lower().startswith('0x') else 10) for word in words)
                if not previous < frame < frames or not 0 <= bits <= 255:
                    raise ValueError('Schedule must be increasing with frames in range and masks 0–255')
                events[frame], previous = bits, frame
            self.bridge.request({'op': 'command', 'command': 'reset'})
            for frame in range(frames):
                if frame in events:
                    self.bridge.request({'op': 'command', 'command': f'input {events[frame]}'})
                result = self.bridge.request({'op': 'replay_frame'})
                if not result.get('ok'):
                    break
            result['output'] = f'Replayed {frame + 1} frames from reset.\n' + result.get('output', '')
            self.revision += 1
        else:
            raise ValueError('Unknown operation')
        result.update(revision=self.revision, title=self.title)
        return 200, result

    def close(self):
        if self.bridge:
            self.bridge.close()
        self.temporary.cleanup()


class Server(HTTPServer):
    def __init__(self, address, model):
        super().__init__(address, Handler)
        self.model = model
        self.token = secrets.token_urlsafe(32)
        self.authority = f'127.0.0.1:{self.server_port}'
        self.origin = f'http://{self.authority}'


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def log_message(self, *_):
        pass  # Never log URL fragments, editor contents, tokens or snapshots.

    def send(self, status, data, mime='application/json; charset=utf-8'):
        if not isinstance(data, bytes):
            data = json.dumps(data, separators=(',', ':')).encode()
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.headers.get('Host') != self.server.authority:
            return self.send(403, {'error': 'Invalid host'})
        files = {'/': ('index.html', 'text/html; charset=utf-8'),
                 '/app.js': ('app.js', 'text/javascript; charset=utf-8'),
                 '/style.css': ('style.css', 'text/css; charset=utf-8')}
        if self.path not in files:
            return self.send(404, {'error': 'Not found'})
        filename, mime = files[self.path]
        self.send(200, (ASSETS / filename).read_bytes(), mime)

    def do_POST(self):
        if (self.path != '/api' or self.headers.get('Host') != self.server.authority or
                self.headers.get('Origin', self.server.origin) != self.server.origin or
                self.headers.get('Sec-Fetch-Site') == 'cross-site' or
                not secrets.compare_digest(self.headers.get('X-Nova-Token', ''), self.server.token)):
            return self.send(403, {'error': 'Invalid local session'})
        try:
            lengths = self.headers.get_all('Content-Length', [])
            if len(lengths) != 1 or self.headers.get('Transfer-Encoding') is not None:
                raise ValueError('Exactly one Content-Length required')
            length = int(lengths[0])
            if not 0 < length <= MAX_BODY or self.headers.get_content_type() != 'application/json':
                raise ValueError('Expected bounded JSON')
            data = self.rfile.read(length)
            if len(data) != length:
                raise ValueError('Incomplete request')
            request = json.loads(data)
            status, response = self.server.model.dispatch(request)
            self.send(status, response)
        except (ValueError, KeyError, TypeError) as error:
            self.send(400, {'error': str(error)})
        except (OSError, RuntimeError, subprocess.TimeoutExpired):
            self.send(503, {'error': 'Local operation failed; load a demo or rebuild to recover'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--no-browser', action='store_true')
    options = parser.parse_args()
    model = Workbench()
    try:
        with Server(('127.0.0.1', options.port), model) as server:
            url = f'{server.origin}/#{server.token}'
            print(f'NOVA Workbench: {url}', flush=True)
            if not options.no_browser:
                webbrowser.open(url)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass
    finally:
        model.close()


if __name__ == '__main__':
    main()

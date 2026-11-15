"""Black-box Workbench acceptance: real-VM parity, protocol and local HTTP safety."""
import http.client
from html.parser import HTMLParser
import re
import json
import pathlib
import struct
import subprocess
import tempfile
import threading
import unittest
from unittest import mock

import workbench as w


class WorkbenchAcceptance(unittest.TestCase):
    def test_buffered_framing_boundaries_and_eof(self):
        rom = w.DEMOS / 'boot_splash.n16'
        # JSON whitespace creates valid messages spanning exact input-buffer
        # boundaries; multiple messages in one write must remain distinct.
        lines = [b' ' * count + b'{}' for count in (8189, 8190, 8191, 8192, 16381, 16382, 16383)]
        process = subprocess.run([w.executable('n16bridge'), str(rom)],
            input=b'\n'.join(lines) + b'\n' + b'X' * 150000 + b'\n{}\r\n{}', capture_output=True, timeout=15)
        responses = [json.loads(line) for line in process.stdout.splitlines()]
        self.assertEqual(process.returncode, 0)
        self.assertEqual(len(responses), len(lines) + 3)
        self.assertTrue(all(item['ok'] for item in responses[:len(lines)]))
        self.assertEqual(responses[-3]['error'], 'RequestTooLarge')
        self.assertTrue(responses[-2]['ok'])
        self.assertTrue(responses[-1]['ok'], 'A final unterminated request executes once at EOF')
        self.assertTrue(all(item['state']['executed_instructions'] == 0 for item in responses if item['ok']))
        # Interactive debugger buffering shares the EOF/oversize recovery rules.
        process = subprocess.run([w.executable('n16dbg'), str(rom)],
            input=b'X' * 8193 + b'\nregs\nstep\nregs', capture_output=True, timeout=15)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(process.stdout.count(b'error: command too long'), 1)
        self.assertIn(b'retired=0', process.stdout)
        self.assertIn(b'retired=1', process.stdout)

    def test_frontend_structure(self):
        class Structure(HTMLParser):
            def __init__(self):
                super().__init__()
                self.ids = []
                self.references = []

            def handle_starttag(self, tag, attrs):
                attrs = dict(attrs)
                if 'id' in attrs:
                    self.ids.append(attrs['id'])
                for key in ('aria-controls', 'aria-labelledby', 'for'):
                    self.references.extend(attrs.get(key, '').split())

        document = Structure()
        document.feed((w.ASSETS / 'index.html').read_text(encoding='utf-8'))
        self.assertEqual(len(document.ids), len(set(document.ids)))
        self.assertLessEqual(set(document.references), set(document.ids))
        script = (w.ASSETS / 'app.js').read_text(encoding='utf-8')
        elements = set(re.findall(r"\$\('([^']+)'\)", script))
        self.assertLessEqual(elements, set(document.ids) | {'syntax'})
        self.assertNotIn('https://', script)  # no remote script/data dependencies

    def test_native_frame_and_pixel_parity(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            for name in w.DEMO_NAMES:
                with self.subTest(name=name):
                    bridge = w.Bridge(w.DEMOS / (name + '.n16'))
                    try:
                        # Debug frames also match canonical frames when no stops are set.
                        for _ in range(3):
                            result = bridge.request({'op': 'frame'})
                            self.assertTrue(result['ok'], result)
                        ppm, wav = directory / 'frame.ppm', directory / 'frame.wav'
                        args = [w.executable('nova16'), 'run', str(w.DEMOS / (name + '.n16')),
                                '--frames', '3', '--screenshot', str(ppm)]
                        if result['profile'] == 2:
                            args += ['--wav', str(wav)]
                        native = json.loads(subprocess.check_output(args, timeout=30))
                        self.assertEqual(native, result['state'])
                        vram, palette = bytes.fromhex(result['vram']), bytes(result['palette'])
                        rgb = bytearray()
                        for i in range(128 * 96):
                            color = (vram[i // 2] >> ((i & 1) * 4)) & 15 if result['display_enabled'] else 0
                            rgb += palette[color * 3:color * 3 + 3]
                        self.assertEqual(ppm.read_bytes(), b'P6\n128 96\n255\n' + rgb)
                        if result['profile'] == 2:
                            self.assertTrue(result['audio']['completed_frame'])
                            native_pcm = wav.read_bytes()[-1600:]
                            self.assertEqual(struct.pack('<800h', *result['audio']['pcm']), native_pcm)
                    finally:
                        bridge.close()

    def test_protocol_rewind_restore_and_failure_atomicity(self):
        bridge = w.Bridge(w.DEMOS / 'nova_sound.n16')
        try:
            initial = bridge.request({'op': 'snapshot'})['snapshot']
            result = bridge.request({'op': 'frame'})
            self.assertEqual(result['history_count'], 1)
            final = bridge.request({'op': 'snapshot'})['snapshot']
            bridge.request({'op': 'command', 'command': 'reverse'})
            self.assertEqual(initial, bridge.request({'op': 'snapshot'})['snapshot'])
            bridge.request({'op': 'frame'})
            self.assertEqual(final, bridge.request({'op': 'snapshot'})['snapshot'])
            result = bridge.request({'op': 'restore', 'data': initial})
            self.assertEqual(result['history_count'], 0)
            bridge.request({'op': 'frame'})
            for payload in [
                {'op': 'restore', 'data': '00' + initial[2:]},
                {'op': 'restore', 'data': 'not hex'},
                {'op': 'restore', 'data': initial[:-2]},
                {'op': 'command', 'command': 'savesnap /tmp/unsafe'},
                {'op': 'command', 'command': 'step 20001'},
                {'op': 'command', 'command': 'step 0xFFFFFFFF'},
                {'version': 2}, {'address': 65535, 'length': 256},
                {'op': 'unknown'}, {'op': 'observe', 'unexpected': True},
            ]:
                with self.subTest(payload=str(payload)[:80]):
                    self.assertFalse(bridge.request(payload)['ok'])
                    self.assertEqual(final, bridge.request({'op': 'snapshot'})['snapshot'])
                    self.assertEqual(bridge.request({'op': 'observe'})['history_count'], 1)
            bridge.request({'op': 'command', 'command': 'input 17'})
            first = bridge.request({'address': 0xd800})
            second = bridge.request({'address': 0xd800})
            self.assertEqual(first['input_pressed'], 17)
            self.assertEqual(first['memory'], second['memory'])
            self.assertEqual(second['input_pressed'], 17)
            self.assertEqual(first['memory'][6], None)  # reserved MMIO
            # Break before execution is a precise stop, not an invented PCM frame.
            bridge.request({'op': 'command', 'command': 'reset'})
            bridge.request({'op': 'command', 'command': 'break 0xe000'})
            result = bridge.request({'op': 'frame'})
            self.assertEqual(result['state']['transition_slots'], 0)
            self.assertTrue(result['stopped'])
            self.assertFalse(result['audio']['completed_frame'])
            # Replay uses the canonical scheduler independent of debugger stops.
            result = bridge.request({'op': 'replay_frame'})
            self.assertEqual(result['state']['transition_slots'], 20000)
        finally:
            bridge.close()
        process = subprocess.run([w.executable('n16bridge'), str(w.DEMOS / 'boot_splash.n16')],
                                 input=b'X' * 160_000 + b'\nnot json\n{}\n', capture_output=True, timeout=10)
        responses = [json.loads(line) for line in process.stdout.splitlines()]
        self.assertEqual(len(responses), 3)
        self.assertEqual(responses[0]['error'], 'RequestTooLarge')
        self.assertEqual(responses[1]['error'], 'BadRequest')
        self.assertTrue(responses[2]['ok'])
        self.assertEqual(process.returncode, 0)

    def test_build_commit_and_replay(self):
        model = w.Workbench()
        try:
            def dispatch(**request):
                status, result = model.dispatch(dict(request, revision=model.revision))
                self.assertEqual(status, 200)
                return result
            before = dispatch(op='vm', request={'op': 'snapshot'})['snapshot']
            failed = dispatch(op='build', source='fn main()->u16 { return true; }')
            self.assertFalse(failed['ok'])
            self.assertIn('TypeMismatch', failed['diagnostics'])
            self.assertEqual(before, dispatch(op='vm', request={'op': 'snapshot'})['snapshot'])
            built = dispatch(op='build', source='fn main()->u16 { return 42; }')
            self.assertTrue(built['ok'])
            self.assertEqual(built['size_report']['rom_payload_bytes'], 92)
            self.assertEqual(len(bytes.fromhex(built['rom'])), 124)
            run = dispatch(op='vm', request={'op': 'command', 'command': 'continue'})
            self.assertTrue(run['state']['halted'])
            self.assertEqual(run['state']['registers'][0], 42)
            # A failed candidate cannot replace a live VM.
            live = model.bridge
            with mock.patch.object(w, 'Bridge', side_effect=RuntimeError('candidate rejected')):
                with self.assertRaises(RuntimeError):
                    model.load_demo('paint')
            self.assertIs(model.bridge, live)
            dispatch(op='load', demo='paint')
            replay = dispatch(op='replay', frames=4, schedule='0 0x10\n2 0')
            self.assertTrue(replay['ok'])
            with tempfile.TemporaryDirectory() as directory:
                schedule = pathlib.Path(directory) / 'input.txt'
                schedule.write_text('0 0x10\n2 0\n')
                native = json.loads(subprocess.check_output([w.executable('nova16'), 'run',
                    str(w.DEMOS / 'paint.n16'), '--frames', '4', '--input', str(schedule)], timeout=30))
            self.assertEqual(replay['state'], native)
            for schedule in ['2 0\n1 0', '0 256', '-1 0', '0 1\n0 2', '4 0', 'garbage']:
                with self.assertRaises(ValueError):
                    dispatch(op='replay', frames=4, schedule=schedule)
            with self.assertRaises(ValueError):
                dispatch(op='load', demo='../../etc/passwd')
            self.assertEqual(len(list(model.directory.iterdir())), 1)
            self.assertEqual(model.dispatch({'op': 'load', 'demo': 'paint', 'revision': -1})[0], 409)
        finally:
            model.close()

    def test_large_valid_inspections_are_bounded_and_recover(self):
        rom = w.DEMOS / 'boot_splash.n16'
        checksum = int.from_bytes(rom.read_bytes()[12:16], 'little')
        with tempfile.TemporaryDirectory() as directory:
            symbols = pathlib.Path(directory) / 'large.map.json'
            symbols.write_text(json.dumps({'schema_version': 2, 'rom_checksum': checksum,
                'symbols': [{'name': 'symbol_' + str(i).zfill(5) + '_' + 'x' * 48,
                             'value': 0xe000} for i in range(3000)], 'locations': []}))
            bridge = w.Bridge(rom, symbols)
            try:
                before = bridge.request({'op': 'snapshot'})['snapshot']
                response = bridge.request({'op': 'command', 'command': 'symbols'})
                self.assertFalse(response['ok'])
                self.assertEqual(response['error'], 'OutputLimit')
                self.assertEqual(before, bridge.request({'op': 'snapshot'})['snapshot'])
                self.assertTrue(bridge.request({'op': 'command', 'command': 'step'})['ok'])
            finally:
                bridge.close()
            entry = 0xe000 + int.from_bytes(rom.read_bytes()[6:8], 'little')
            symbols.write_text(json.dumps({'schema_version': 2, 'rom_checksum': checksum,
                'symbols': [], 'locations': [{'address': entry, 'length': 2,
                'file': 'x' * 600000, 'line': 1, 'column': 1}]}))
            bridge = w.Bridge(rom, symbols)
            try:
                self.assertEqual(bridge.initial['error'], 'OutputLimit')
                self.assertEqual(bridge.request({'op': 'command', 'command': 'step'})['state']['executed_instructions'], 1)
                self.assertTrue(bridge.request({'op': 'snapshot'})['ok'])
            finally:
                bridge.close()

    def test_imported_rom_validation_commit_and_retention(self):
        model = w.Workbench()
        try:
            def dispatch(**request):
                status, result = model.dispatch(dict(request, revision=model.revision))
                self.assertEqual(status, 200)
                return result
            for name in ('paint', 'nova_sound'):
                rom = (w.DEMOS / (name + '.n16')).read_bytes()
                result = dispatch(op='load_rom', data=rom.hex())
                self.assertTrue(result['ok'])
                self.assertEqual(result['title'], 'Imported ROM')
                self.assertEqual(result['profile'], 2 if name == 'nova_sound' else 1)
                dispatch(op='vm', request={'op': 'frame'})
                before = dispatch(op='vm', request={'op': 'snapshot'})['snapshot']
                bad_crc = bytearray(rom)
                bad_crc[-1] ^= 1
                for bad in ('', '00', rom[:-1].hex(), bytes(bad_crc).hex()):
                    rejected = dispatch(op='load_rom', data=bad)
                    self.assertFalse(rejected['ok'])
                    self.assertEqual(before, dispatch(op='vm', request={'op': 'snapshot'})['snapshot'])
                for bad in (None, [], 'x', '00 00', '00' * 8225):
                    with self.assertRaises(ValueError):
                        dispatch(op='load_rom', data=bad)
                self.assertEqual(len(list(model.directory.iterdir())), 1, 'Only current imported assets are retained')
        finally:
            model.close()

    def test_native_replay_grammar_and_actual_completed_count(self):
        cases = json.loads((w.ROOT / 'docs/quality/replay-cases.json').read_text(encoding='utf-8'))
        model = w.Workbench()
        try:
            def dispatch(**request):
                status, result = model.dispatch(dict(request, revision=model.revision))
                self.assertEqual(status, 200)
                return result
            dispatch(op='load', demo='paint')
            for text in cases['valid']:
                result = dispatch(op='replay', frames=4, schedule=text)
                self.assertEqual(result['replay_frames'], 4)
            before = dispatch(op='vm', request={'op': 'snapshot'})['snapshot']
            for text in cases['invalid'] + ['#' + 'é' * 4096]:
                with self.subTest(schedule=text[:40]), self.assertRaises(ValueError):
                    dispatch(op='replay', frames=4, schedule=text)
                self.assertEqual(before, dispatch(op='vm', request={'op': 'snapshot'})['snapshot'])
            dispatch(op='build', source='fn main()->u16{return 42;}')
            result = dispatch(op='replay', frames=120, schedule='')
            self.assertEqual(result['replay_frames'], 1)
            self.assertIn('1 of 120', result['output'])
            self.assertEqual(result['state']['frame_count'], 1)
            dispatch(op='build', source='fn main()->u16{return 42;}', architecture='nova16-v2')
            result = dispatch(op='replay', frames=120, schedule='')
            self.assertEqual(result['replay_frames'], 120, 'V2 devices continue while CPU is halted')
            self.assertEqual(result['state']['transition_slots'], 2_400_000)
        finally:
            model.close()

    def test_http_boundaries_and_assets(self):
        model = w.Workbench()
        server = w.Server(('127.0.0.1', 0), model)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            def request(method, path, data=None, **headers):
                connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=10)
                headers = {'Host': server.authority, **headers}
                if data is not None:
                    data = json.dumps(data).encode()
                    headers.setdefault('Content-Type', 'application/json')
                    headers.setdefault('X-Nova-Token', server.token)
                connection.request(method, path, body=data, headers=headers)
                response = connection.getresponse()
                result = response.status, response.read(), dict(response.headers)
                connection.close()
                return result
            for path in ['/', '/style.css', '/app.js']:
                status, body, headers = request('GET', path)
                self.assertEqual(status, 200)
                self.assertTrue(body)
                self.assertIn("frame-ancestors 'none'", headers['Content-Security-Policy'])
                self.assertEqual(headers['Cache-Control'], 'no-store')
            self.assertEqual(request('GET', '/../../etc/passwd')[0], 404)
            self.assertEqual(request('GET', '/', Host='evil.invalid')[0], 403)
            self.assertEqual(request('POST', '/api', {'op': 'bootstrap'}, Origin='https://evil.invalid')[0], 403)
            self.assertEqual(request('POST', '/api', {'op': 'bootstrap'}, **{'X-Nova-Token': 'bad'})[0], 403)
            self.assertEqual(request('POST', '/api', [])[0], 400)
            # Reject at headers, without racing a large body against an early close.
            # macOS may reset a socket with unread inbound data; sending that body
            # tests transport timing, not the server's advertised size boundary.
            connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=10)
            connection.putrequest('POST', '/api', skip_host=True)
            for key, value in {'Host': server.authority, 'X-Nova-Token': server.token,
                               'Content-Type': 'application/json',
                               'Content-Length': str(w.MAX_BODY + 1)}.items():
                connection.putheader(key, value)
            connection.endheaders()
            response = connection.getresponse()
            self.assertEqual(response.status, 400)
            response.read()
            connection.close()
            self.assertEqual(request('POST', '/api', {'op': 'bootstrap'})[0], 200)
        finally:
            server.shutdown()
            worker.join(timeout=5)
            server.server_close()
            model.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)

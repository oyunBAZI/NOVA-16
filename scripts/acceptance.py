#!/usr/bin/env python3
"""Black-box acceptance, using only the shipped CLIs and Python's standard library."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'zig-out' / 'bin'
DEMOS = ('boot_splash', 'bouncing_pixel', 'paint', 'diagnostics')


def run(*args, stdin=None, success=True):
    p = subprocess.run([str(a) for a in args], input=stdin, text=True,
                       capture_output=True, timeout=30, cwd=ROOT)
    if (p.returncode == 0) != success:
        raise AssertionError(f'{args}: exit {p.returncode}\n{p.stdout}\n{p.stderr}')
    return p


def main():
    with tempfile.TemporaryDirectory(prefix='nova16-acceptance-') as temp:
        temp = Path(temp)
        for demo in DEMOS:
            source = ROOT / 'examples' / f'{demo}.asm'
            rom, symbols = temp / f'{demo}.n16', temp / f'{demo}.sym'
            run(BIN / 'n16asm', source, '--out', rom, '--symbols', symbols)
            assert symbols.read_text().strip()
            assert rom.read_bytes() == (ROOT / 'zig-out/demos' / rom.name).read_bytes()
            assert 'N16R v1' in run(BIN / 'nova16', 'inspect', rom).stdout
            screenshot, state = temp / f'{demo}.ppm', temp / f'{demo}.json'
            p = run(BIN / 'nova16', 'run', rom, '--headless', '--frames', '140',
                    '--screenshot', screenshot, '--state-json', state)
            parsed = json.loads(p.stdout)
            assert parsed == json.loads(state.read_text())
            assert not parsed['trapped']
            assert parsed['sp'] == 0xbffe
            assert parsed['executed_instructions'] > 0
            ppm = screenshot.read_bytes()
            assert ppm.startswith(b'P6\n128 96\n255\n') and len(ppm) == 36878
            digest = hashlib.sha256(ppm).hexdigest()
            if demo == 'boot_splash':
                assert digest == '420c5fc58a7f204072d9dd257e24607f2d624f3b31a39c154cf5c8cb0152955c'
                assert parsed['halted'] and parsed['frame_count'] == 5
            if demo == 'diagnostics':
                assert digest == 'b46b81b0ff39fe8e0e92b2ffd76c0107835e577e17d2f1e050adfea043ea3df6'
                assert parsed['registers'][7] == 0x600d and parsed['halted']
            session = run(BIN / 'n16dbg', rom, '--symbols', symbols,
                          stdin='break 0xe000\ncontinue 3\nregs\nstep\ndisasm 0xe000 2\nstack 2\nquit\n').stdout
            assert 'breakpoint before e000' in session
            assert 'retired=0' in session and 'start:' in session
            print(f'{demo}: boot/debug/PPM OK, sha256={digest}')

        schedule = temp / 'input.txt'
        schedule.write_text('0 24\n20 18\n40 0\n')
        paint = temp / 'paint.n16'
        cmd = (BIN / 'nova16', 'run', paint, '--headless', '--frames', '60', '--input', schedule)
        assert run(*cmd).stdout == run(*cmd).stdout
        baseline = json.loads(run(BIN / 'nova16', 'run', paint, '--frames', '60').stdout)
        replay = json.loads(run(*cmd).stdout)
        assert baseline['vram_checksum'] != replay['vram_checksum']
        capped = json.loads(run(BIN / 'nova16', 'run', paint, '--frames', '100', '--max-instructions', '7').stdout)
        assert capped['executed_instructions'] == 7

        for options in (('--gui', '--headless'), ('--frames', '-1'), ('--wat', '1'),
                        ('--frames',), ('--frames', '1', '--frames', '2'),
                        ('--headless', '--scale', '4'), ('--gui', '--input', str(schedule))):
            run(BIN / 'nova16', 'run', paint, *options, success=False)
        bad = temp / 'bad.asm'
        for source in ('LDI R8, 0', '.fill 8193', 'B.EQ 0xe600', '.ascii "unterminated',
                       '.equ a, b\n.equ b, a\nHALT'):
            bad.write_text(source)
            p = run(BIN / 'n16asm', bad, '--out', temp / 'bad.n16', success=False)
            assert str(bad) + ':1:' in p.stderr
        bad.write_text('  .entry missing\nHALT\n')
        diagnostic = json.loads(run(BIN / 'n16asm', bad, '--out', temp / 'bad.n16',
                                   '--diagnostics', 'json', success=False).stderr)
        assert (diagnostic['line'], diagnostic['column'], diagnostic['token']) == (1, 10, 'missing')
        listing, debug_map = temp / 'program.lst', temp / 'program.sym2'
        run(BIN / 'n16asm', ROOT / 'examples/paint.asm', '--out', paint,
            '--listing', listing, '--debug-symbols', debug_map)
        assert 'e000:' in listing.read_text() and json.loads(debug_map.read_text())['schema_version'] == 2
        run(BIN / 'n16dbg', paint, '--symbols', debug_map, stdin='quit\n')
        wrong_map = json.loads(debug_map.read_text()); wrong_map['rom_checksum'] ^= 1
        debug_map.write_text(json.dumps(wrong_map))
        run(BIN / 'n16dbg', paint, '--symbols', debug_map, stdin='quit\n', success=False)
        malformed = temp / 'malformed.n16' 
        valid = (temp / 'boot_splash.n16').read_bytes()
        for content in (b'', valid[:31], b'BAD!' + valid[4:], valid + b'\0', valid[:-1]):
            malformed.write_bytes(content)
            run(BIN / 'nova16', 'inspect', malformed, success=False)
        dbg = run(BIN / 'n16dbg', paint, stdin='step nope\nwatch 0xffff\nmem 65535 2\nquit\n').stdout
        assert dbg.count('error:') == 3
        snapshot = temp / 'machine.n16s'
        session = run(BIN / 'n16dbg', paint, stdin=(
            f'history 8\ninput 24\nstep 4\ntrace 4\nsavesnap {snapshot}\n'
            f'frame 2\nloadsnap {snapshot}\ndevices\nreverse\nquit\n')).stdout
        assert snapshot.read_bytes().startswith(b'N16S') and 'opcode=' in session
        assert 'held=18' in session and 'error: HistoryEmpty' in session
        print('Replay, budgets, malformed CLI/source/ROM/debugger and snapshot checks OK')


if __name__ == '__main__':
    main()

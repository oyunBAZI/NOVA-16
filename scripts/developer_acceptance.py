"""Black-box developer-tool contracts; run on every native CI target."""
import json
import pathlib
import subprocess
import tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = ROOT / 'zig-out/bin'
def run(tool, *args, ok=True, stdin=None):
    p = subprocess.run([str(BIN / tool), *map(str, args)], input=stdin, text=True,
                       capture_output=True, timeout=30, cwd=ROOT)
    assert (p.returncode == 0) == ok, (p.args, p.returncode, p.stdout, p.stderr)
    return p

def main():
    with tempfile.TemporaryDirectory() as directory:
        p = pathlib.Path(directory)
        source, rom, sym = p/'main.asm', p/'main.n16', p/'main.sym2'
        source.write_text('LDI R0, 7\nHALT\n')
        run('n16asm', source, '--out', rom, '--debug-symbols', sym)
        previous = rom.read_bytes()
        run('n16asm', source, '--out', rom, '--listing', p/'missing/x.lst', ok=False)
        assert rom.read_bytes() == previous
        run('n16asm', source, '--out', rom, '--symbols', rom, ok=False)
        assert rom.read_bytes() == previous
        run('n16asm', source, '--out', source, ok=False)
        assert source.read_text().startswith('LDI')
        source.write_text('LDI R8, 0\nLDI R9, 0\nHALT\n')
        errors = json.loads(run('n16asm', source, '--out', rom, '--diagnostics', 'json2', ok=False).stderr)
        assert errors['schema_version'] == 2
        assert [d['line'] for d in errors['diagnostics']] == [1, 2]
        assert errors['diagnostics'][1]['excerpt'] == 'LDI R9, 0'
        assert rom.read_bytes() == previous
        assert '^' in run('n16asm', source, '--out', rom, '--diagnostics', 'rich', ok=False).stderr
        # Reproducible maps/ROMs across unrelated absolute checkout paths.
        import shutil
        for name in ('first', 'second'):
            shutil.copytree(ROOT/'examples/projects/counter', p/name)
            run('n16asm', p/name/'main.asm', '--project-root', p/name,
                '--out', p/(name+'.n16'), '--debug-symbols', p/(name+'.sym2'))
        assert (p/'first.n16').read_bytes() == (p/'second.n16').read_bytes()
        assert (p/'first.sym2').read_bytes() == (p/'second.sym2').read_bytes()
        mapping = json.loads((p/'first.sym2').read_text())
        assert 'lib/input.asm' in {x['file'] for x in mapping['locations']}
        state = json.loads(run('nova16', 'run', p/'first.n16').stdout)
        assert state['halted'] and state['registers'][1] == 42
        snap, restored = p/'before.n16s', p/'restored.n16s'
        session = run('n16dbg', p/'first.n16', '--symbols', p/'first.sym2', stdin=(
            'history 8\nbreak lib/graphics.asm:2\ncontinue 100\nregs\nsymbols\nsource\n'
            'next\nstep\nreverse\nregs\nmem result 2\n'
            f'savesnap {snap}\nstep\nloadsnap {snap}\nsavesnap {restored}\n'
            'continue 100\nregs\nquit\n')).stdout
        assert 'breakpoint before' in session and 'at lib/graphics.asm:2:' in session
        assert 'initialize=' in session and '0100: 00 00' in session
        assert 'R1=002a' in session and 'HALT' in session
        assert snap.read_bytes() == restored.read_bytes()
        inspection = json.loads(run('nova16', 'inspect', p/'first.n16', '--json').stdout)
        assert inspection['schema_version'] == 1 and inspection['entry_address'] == 0xe000
        import sys, zipfile, hashlib
        test = p/'counter-test.json'
        test.write_text(json.dumps({'schema_version': 1, 'rom': 'first.n16', 'frames': 120,
                                   'registers': {'1': 42}, 'halted': True}))
        for script, arguments in [('rom_test.py', [test]),
                                  ('guest_package.py', [p/'first', '--out', p/'guest.zip']),
                                  ('guest_package.py', [p/'first', '--out', p/'guest-again.zip'])]:
            subprocess.run([sys.executable, str(ROOT/'scripts'/script), *map(str, arguments)], check=True,
                           capture_output=True, timeout=30, cwd=ROOT)
        assert (p/'guest.zip').read_bytes() == (p/'guest-again.zip').read_bytes()
        with zipfile.ZipFile(p/'guest.zip') as archive:
            archive.extractall(p/'guest')
        manifest = json.loads((p/'guest/guest-manifest.json').read_text())
        for name, digest in manifest['files'].items():
            assert hashlib.sha256((p/'guest'/name).read_bytes()).hexdigest() == digest
        run('n16asm', p/'guest/src/main.asm', '--project-root', p/'guest/src', '--out', p/'rebuilt.n16')
        assert (p/'rebuilt.n16').read_bytes() == (p/'guest/program.n16').read_bytes()
        entry = p/'first/main.asm'  
        for text in ('.include "main.asm"', '.include "missing.asm"',
                     '.include "../outside.asm"', '.include "/absolute.asm"'):
            entry.write_text(text)
            (p/'outside.asm').write_text('HALT')
            run('n16asm', entry, '--project-root', p/'first', '--out', rom, ok=False)
            assert rom.read_bytes() == previous
        entry.write_text('.include "lib/input.asm"\n.include "lib/input.asm"')
        run('n16asm', entry, '--out', rom, ok=False)
    print('Developer diagnostics, bounded recovery, output preflight/staging OK')
if __name__ == '__main__':
    main()

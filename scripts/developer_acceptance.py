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

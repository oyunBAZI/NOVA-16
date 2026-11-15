"""Verify a distributable without requiring Zig, SDL, or repository source files."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

archive = Path(sys.argv[1]).resolve()
assert hashlib.sha256(archive.read_bytes()).hexdigest() == archive.with_suffix('.zip.sha256').read_text().split()[0]
with tempfile.TemporaryDirectory(prefix='nova16-package-') as temp:
    base = Path(temp)
    with zipfile.ZipFile(archive) as package:
        assert len(package.infolist()) <= 1000 and sum(item.file_size for item in package.infolist()) < 64 * 1024 * 1024
        for item in package.infolist():
            path = Path(item.filename)
            if path.is_absolute() or path.drive or '..' in path.parts or '\\' in item.filename:
                raise ValueError('unsafe release path')
        package.extractall(base)
        for item in package.infolist():
            if '/bin/' in item.filename:
                os.chmod(base / item.filename, 0o755)
    root, = base.iterdir()
    manifest = json.loads((root / 'manifest.json').read_text())
    assert manifest['package_schema'] == 1 and manifest['frontend'] == 'headless'
    for name, info in manifest['files'].items():
        assert not Path(name).is_absolute() and '..' not in Path(name).parts and '\\' not in name
        data = (root / name).read_bytes()
        assert len(data) == info['size'] and hashlib.sha256(data).hexdigest() == info['sha256']
    suffix = '.exe' if sys.platform == 'win32' else ''
    def run(exe, *args, stdin=None):
        result = subprocess.run([str(root / 'bin' / (exe + suffix)), *map(str, args)],
                                input=stdin, capture_output=True, text=True, check=True,
                                cwd=root, timeout=30)
        return result.stdout
    for exe in ('nova16', 'n16asm', 'n16dbg', 'n16c'):
        assert run(exe, '--version').strip() == manifest['version']
    assert json.loads(run('nova16', '--build-info')) == manifest['build_info']
    for demo in ('boot_splash', 'bouncing_pixel', 'paint', 'diagnostics'):
        generated = root / (demo + '.n16')
        run('n16asm', root / 'examples' / (demo + '.asm'), '--out', generated)
        assert generated.read_bytes() == (root / 'demos' / generated.name).read_bytes()
        state = json.loads(run('nova16', 'run', generated, '--headless', '--frames', '140'))
        assert not state['trapped'] and state['executed_instructions'] > 0
        if demo == 'diagnostics':
            assert state['registers'][7] == 0x600d
        session = run('n16dbg', generated, stdin='regs\nstep\nquit\n')
        assert 'PC=' in session
    # New developer workflow must also work using only extracted tools/files.
    for project in ('counter', 'breakout'):
        source = root/'examples/projects'/project/'main.asm'
        generated, symbols = root/(project+'.n16'), root/(project+'.sym2')
        run('n16asm', source, '--project-root', source.parent, '--out', generated, '--debug-symbols', symbols)
        inspection = json.loads(run('nova16', 'inspect', generated, '--json'))
        assert inspection['schema_version'] == 1
        if project == 'breakout':
            assert generated.read_bytes() == (root/'demos/breakout.n16').read_bytes()
        state = json.loads(run('nova16', 'run', generated, '--frames', '10'))
        assert not state['trapped']
        location = 'lib/graphics.asm:2' if project == 'counter' else 'entry.asm:5'
        snapshot = root/(project+'.n16s')
        session = run('n16dbg', generated, '--symbols', symbols, stdin=(
            f'history 8\nbreak {location}\ncontinue 100\nsource\nnext\nstep\nreverse\n'
            f'savesnap {snapshot}\nstep\nloadsnap {snapshot}\nregs\nquit\n'))
        assert 'breakpoint before' in session and 'error:' not in session
        assert snapshot.read_bytes().startswith(b'N16S')
    hashes = json.loads((root/'docs/gameplay/hashes.json').read_text())
    for scene, schedule in [('win','win-input.txt'), ('loss','right-input.txt')]:
        shot = root/(scene+'.ppm')
        run('nova16', 'run', root/'demos/breakout.n16', '--frames', '1000', '--max-instructions', '20000000',
            '--input', root/'docs/gameplay'/schedule, '--screenshot', shot)
        assert hashlib.sha256(shot.read_bytes()).hexdigest() == hashes[scene]
    for script in ('compatibility_acceptance.py', 'compiler_acceptance.py', 'project_acceptance.py', 'application_acceptance.py', 'v2_contract_vectors.py', 'v2_acceptance.py'):
        subprocess.run([sys.executable, str(root/'scripts'/script)], cwd=root, check=True, timeout=180)
    for app in ('crates', 'pixel_studio'):
        destination = root/(app+'-project')
        with zipfile.ZipFile(root/'applications'/(app+'.zip')) as project:
            project.extractall(destination)
        subprocess.run([sys.executable, str(root/'scripts/n16.py'), 'test', str(destination)], cwd=root, check=True, timeout=120)
    print(f"Package {manifest['version']} {manifest['os']}/{manifest['arch']}: checksums, assembly, boot and debugger passed")

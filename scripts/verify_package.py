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
    for exe in ('nova16', 'n16asm', 'n16dbg'):
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
    print(f"Package {manifest['version']} {manifest['os']}/{manifest['arch']}: checksums, assembly, boot and debugger passed")

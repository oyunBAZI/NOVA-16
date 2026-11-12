"""Build a deterministic native headless release ZIP and checksum manifest."""
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import time
import zipfile

root = Path(__file__).resolve().parents[1]
version = re.search(r'\.version\s*=\s*"([^"]+)"', (root / 'build.zig.zon').read_text()).group(1)
system = {'Linux': 'linux', 'Darwin': 'macos', 'Windows': 'windows'}[platform.system()]
arch = {'AMD64': 'x86_64', 'x86_64': 'x86_64', 'arm64': 'aarch64', 'aarch64': 'aarch64'}[platform.machine()]
name = f'nova16-{version}-{system}-{arch}'
files = {}
for exe in ('nova16', 'n16asm', 'n16dbg'):
    path = Path('bin') / (exe + ('.exe' if system == 'windows' else ''))
    files[path.as_posix()] = (root / 'zig-out' / path).read_bytes()
for path in sorted((root / 'zig-out/demos').glob('*')):
    if path.suffix in ('.n16', '.sym', '.sym2'):
        files['demos/' + path.name] = path.read_bytes()
for pattern in ('docs/**/*.md', 'docs/**/*.png', 'docs/**/*.json', 'docs/gameplay/*.txt', 'examples/**/*.asm', 'scripts/rom_test.py', 'scripts/guest_package.py'):
    for path in sorted(root.glob(pattern)):
        files[path.relative_to(root).as_posix()] = path.read_bytes()
for filename in ('README.md', 'INSTALL.md', 'LICENSE', 'CHANGELOG.md', 'SECURITY.md', 'CONTRIBUTING.md'):
    files[filename] = (root / filename).read_bytes()
build_info = json.loads(subprocess.check_output([str(root / 'zig-out/bin' / ('nova16.exe' if system == 'windows' else 'nova16')), '--build-info'], text=True))
assert build_info['arch'] == arch and not build_info['gui'] and build_info['optimization'] == 'safe', 'package a native ReleaseSafe headless build'
manifest = {'build_info': build_info, 'package_schema': 1, 'version': version, 'zig_version': '0.17.1',
            'isa_version': 1, 'rom_version': 1, 'snapshot_version': 1,
            'os': system, 'arch': arch, 'frontend': 'headless',
            'source_dirty': subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--', 'src', 'build.zig', 'build.zig.zon', 'scripts', 'docs', 'examples', 'README.md', 'INSTALL.md'], cwd=root).returncode != 0 or bool(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', 'src', 'examples', 'scripts', 'docs'], cwd=root)),
            'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
            'files': {name: {'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)} for name, data in sorted(files.items())}}
files['manifest.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
files['SHA256SUMS'] = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name, data in sorted(files.items())).encode()
dist = root / 'dist'; dist.mkdir(exist_ok=True)
archive = dist / (name + '.zip')
epoch = int(subprocess.check_output(['git', 'show', '-s', '--format=%ct', 'HEAD'], cwd=root, text=True))
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
    for filename, data in sorted(files.items()):
        entry = zipfile.ZipInfo(name + '/' + filename, time.gmtime(epoch)[:6])
        entry.create_system = 3
        entry.external_attr = (0o100755 if filename.startswith('bin/') else 0o100644) << 16
        entry.compress_type = zipfile.ZIP_DEFLATED
        package.writestr(entry, data, compresslevel=9)
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.zip.sha256').write_text(f'{checksum}  {archive.name}\n')
print(archive)

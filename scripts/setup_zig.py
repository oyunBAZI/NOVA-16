"""Install exact, checksum-pinned official Zig binaries; usable in CI or locally."""
import hashlib
import json
import os
from pathlib import Path
import platform
import tarfile
import urllib.request
import zipfile

system = {'Linux': 'linux', 'Windows': 'windows', 'Darwin': 'macos'}[platform.system()]
arch = {'AMD64': 'x86_64', 'x86_64': 'x86_64', 'arm64': 'aarch64', 'aarch64': 'aarch64'}[platform.machine()]
release = json.loads(Path(__file__).with_name('toolchains.json').read_text())[f'{arch}-{system}']
root = Path(os.environ.get('RUNNER_TEMP', '.zig-toolchain')).resolve()
root.mkdir(parents=True, exist_ok=True)
archive = root / Path(release['tarball']).name
urllib.request.urlretrieve(release['tarball'], archive)
if not (hashlib.sha256(archive.read_bytes()).hexdigest() == release['shasum']):
    raise ValueError('Zig checksum mismatch')
if archive.suffix == '.zip':
    with zipfile.ZipFile(archive) as package:
        package.extractall(root)
else:
    with tarfile.open(archive) as package:
        package.extractall(root, filter='data')
location = root / archive.name.removesuffix('.tar.xz').removesuffix('.zip')
if 'GITHUB_PATH' in os.environ:
    with open(os.environ['GITHUB_PATH'], 'a', encoding='utf-8') as out:
        out.write(str(location) + '\n')
print(location)

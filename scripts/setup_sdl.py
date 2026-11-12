"""Build genuine SDL2 2.32.4 from a pinned official source archive (CMake required)."""
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import urllib.request
URL = 'https://www.libsdl.org/release/SDL2-2.32.4.tar.gz'
SHA256 = 'f15b478253e1ff6dac62257ded225ff4e7d0c5230204ac3450f1144ee806f934'
root = Path(__file__).resolve().parents[1]
prefix = (root/'.sdl-sdk').resolve()
with tempfile.TemporaryDirectory(prefix='nova16-sdl-') as directory:
    temp = Path(directory)
    archive = temp/'sdl.tar.gz'
    with urllib.request.urlopen(URL, timeout=60) as response, archive.open('wb') as output:
        size = 0
        while chunk := response.read(1024*1024):
            size += len(chunk)
            if size > 16*1024*1024:
                raise ValueError('SDL archive exceeds bound')
            output.write(chunk)
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == SHA256, 'SDL checksum mismatch'
    with tarfile.open(archive) as source:
        source.extractall(temp, filter='data')
    subprocess.run(['cmake', '-S', str(temp/'SDL2-2.32.4'), '-B', str(temp/'build'),
                    '-DCMAKE_BUILD_TYPE=Release', '-DSDL_SHARED=ON', '-DSDL_STATIC=OFF',
                    '-DSDL_TEST=OFF', '-DSDL_TESTS=OFF', '-DSDL_INSTALL_TESTS=OFF',
                    '-DCMAKE_INSTALL_PREFIX='+str(prefix), '-DCMAKE_INSTALL_NAME_DIR='+str(prefix/'lib')], check=True, timeout=180)
    subprocess.run(['cmake', '--build', str(temp/'build'), '--config', 'Release', '--parallel', '3'], check=True, timeout=600)
    subprocess.run(['cmake', '--install', str(temp/'build'), '--config', 'Release'], check=True, timeout=120)
if 'GITHUB_ENV' in os.environ:
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write('NOVA_SDL_PREFIX='+str(prefix)+'\n')
print(prefix)

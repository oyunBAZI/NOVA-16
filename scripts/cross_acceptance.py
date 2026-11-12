"""Cross-build regression: all asset generators must run on the host."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='nova16-cross-') as tmp:
    baseline = None
    for target in ('native', 'x86_64-windows', 'aarch64-macos', 'x86_64-macos'):
        prefix = Path(tmp) / target
        subprocess.run(['zig', 'build', f'-Dtarget={target}', '-Doptimize=ReleaseSafe',
                        '--prefix', str(prefix)], cwd=root, check=True, timeout=300)
        images = {p.name: p.read_bytes() for p in (prefix / 'demos').glob('*.n16')}
        assert len(images) == 4, target
        if baseline is None:
            baseline = images
        assert images == baseline, f'{target}: assets differ'
        print(f'{target}: build and ROM identity passed')

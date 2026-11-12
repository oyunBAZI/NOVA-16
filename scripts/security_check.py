"""Fail closed on floating Actions/toolchain pins and dangerous workflow triggers."""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
for path in (root / '.github/workflows').glob('*.yml'):
    text = path.read_text()
    assert 'pull_request_target:' not in text, path
    assert '--insecure' not in text and 'curl -k ' not in text, path
    assert 'permissions:\n  contents: read' in text, path
    for reference in re.findall(r'uses:\s*([^\s#]+)', text):
        if reference.startswith('./.github/workflows/'):
            assert (root / reference).is_file(), reference
        else:
            assert re.fullmatch(r'actions/[a-z-]+@[0-9a-f]{40}', reference), reference
    assert 'persist-credentials: true' not in text
for name, pin in json.loads((root / 'scripts/toolchains.json').read_text()).items():
    assert pin['tarball'].startswith('https://ziglang.org/download/0.17.1/')
    assert re.fullmatch('[0-9a-f]{64}', pin['shasum']), name
version = re.search(r'\.version\s*=\s*"([^"]+)"', (root / 'build.zig.zon').read_text()).group(1)
assert f'"{version}"' in (root / 'src/version.zig').read_text()
assert 'eol=lf' in (root / '.gitattributes').read_text()
print('Workflow pin/trigger/permissions, toolchain SHA256, version and source checkout policy passed')

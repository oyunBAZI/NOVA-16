"""Verify downloaded cross-OS SDK archives without executing foreign binaries."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile


def safe(name):
    return bool(name) and not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts and '\\' not in name and ':' not in name


def verify(directory):
    results = []
    for archive in sorted(directory.glob('*.zip')):
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        assert archive.with_suffix('.zip.sha256').read_text(encoding='utf-8').split() == [digest, archive.name]
        with zipfile.ZipFile(archive) as sdk:
            members = sdk.infolist()
            names = {item.filename for item in members}
            assert len(names) == len(members) <= 1500
            assert sum(item.file_size for item in members) < 64 * 1024 * 1024
            assert all(safe(item.filename) and not item.is_dir() for item in members)
            prefix = archive.stem + '/'
            assert all(name.startswith(prefix) for name in names)
            manifest = json.loads(sdk.read(prefix + 'manifest.json'))
            assert manifest['package_schema'] == 1 and manifest['frontend'] == 'headless'
            assert manifest['source_dirty'] is False
            assert manifest['supported_profiles'] == [1, 2]
            expected = {prefix + name for name in manifest['files']} | {prefix + 'manifest.json', prefix + 'SHA256SUMS'}
            assert names == expected, 'Every transferred archive member must be declared'
            for name, info in manifest['files'].items():
                assert safe(name)
                data = sdk.read(prefix + name)
                assert len(data) == info['size'] and hashlib.sha256(data).hexdigest() == info['sha256']
            sums = sdk.read(prefix + 'SHA256SUMS').decode('utf-8').splitlines()
            assert len(sums) == len(manifest['files']) + 1
            for line in sums:
                expected_hash, name = line.split('  ', 1)
                assert safe(name) and hashlib.sha256(sdk.read(prefix + name)).hexdigest() == expected_hash
            results.append({'archive': archive.name, 'sha256': digest, 'os': manifest['os'],
                            'arch': manifest['arch'], 'version': manifest['version'],
                            'commit': manifest['commit'], 'verified_files': len(names)})
    assert len(results) == 3 and {item['os'] for item in results} == {'linux', 'windows', 'macos'}
    assert len({item['commit'] for item in results}) == 1, 'All packages must use the same tested source revision'
    assert len({item['version'] for item in results}) == 1
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--out', type=Path, default=Path('zig-out/artifact-acceptance.json'))
    args = parser.parse_args()
    report = {'schema_version': 1, 'passed': False}
    try:
        report['packages'] = verify(args.directory)
        report['passed'] = True
    except Exception as error:
        report['failure'] = str(error)
        raise
    finally:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()

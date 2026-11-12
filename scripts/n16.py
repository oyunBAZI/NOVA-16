"""NOVA-16 reproducible local project workflow (Python 3.10+). No downloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tempfile
import zipfile

LIMIT = 1024 * 1024

def json_bytes(value):
    return (json.dumps(value, sort_keys=True, indent=2)+'\n').encode()

def execute(binary, *args, capture=False, **kw):
    return subprocess.run([str(binary), *map(str, args)], check=True,
                          capture_output=capture, text=True, timeout=60 if capture else None, **kw)

def tool(bins, name):
    result = bins/(name + ('.exe' if os.name == 'nt' else ''))
    if not result.is_file():
        raise ValueError(f'missing {result}; build NOVA-16 or supply --bin-dir')
    return result

def load(root):
    if (root/'n16-project.json').is_symlink():
        raise ValueError('symlink manifest')
    with (root/'n16-project.json').open('rb') as stream:
        raw = stream.read(65537)
    if len(raw) > 65536:
        raise ValueError('manifest limit')
    manifest = json.loads(raw)
    if not isinstance(manifest, dict) or set(manifest) != {'schema_version', 'name', 'language', 'entry', 'files', 'tests'} or (type(manifest['schema_version']) is not int or manifest['schema_version'] != 1):
        raise ValueError('unsupported project manifest')
    if not isinstance(manifest['name'], str) or not 1 <= len(manifest['name']) <= 64:
        raise ValueError('invalid name')
    if manifest['language'] not in ('n16c', 'asm'):
        raise ValueError('language must be n16c or asm')
    names = manifest['files']
    if not isinstance(names, list) or not 1 <= len(names) <= 128 or not all(isinstance(name, str) and name for name in names) or len({name.casefold() for name in names}) != len(names):
        raise ValueError('invalid file list')
    files = {}
    for name in names:
        if not isinstance(name, str) or '\\' in name or ':' in name:
            raise ValueError('invalid project file')
        path = PurePosixPath(name)
        if str(path) != name or path.is_absolute() or '..' in path.parts or path.parts[0] == '.n16' or name in ('n16-project.json', 'package-manifest.json'):
            raise ValueError('non-local or reserved file')
        candidate = root/path
        if any((root.joinpath(*path.parts[:i])).is_symlink() for i in range(1, len(path.parts)+1)):
            raise ValueError('symlink project input')
        with candidate.open('rb') as stream:
            data = stream.read(LIMIT+1)
        files[name] = data
        if sum(map(len, files.values())) > LIMIT:
            raise ValueError('project byte limit')
    if not isinstance(manifest['entry'], str) or manifest['entry'] not in files:
        raise ValueError('entry must be declared')
    tests = manifest['tests']
    if not isinstance(tests, list) or len(tests) > 64:
        raise ValueError('test limit')
    for test in tests:
        if not isinstance(test, dict) or set(test)-{'frames', 'input', 'registers', 'halted', 'ppm_sha256'}:
            raise ValueError('invalid test fields')
        if type(test.get('frames')) is not int or not 1 <= test['frames'] <= 10000:
            raise ValueError('test frame limit')
        if 'input' in test and (not isinstance(test['input'], str) or test['input'] not in files):
            raise ValueError('test input must be declared')
        if 'halted' in test and type(test['halted']) is not bool:
            raise ValueError('invalid halted expectation')
        if not isinstance(test.get('registers', {}), dict):
            raise ValueError('invalid register expectations')
        for index, value in test.get('registers', {}).items():
            if index not in tuple(map(str, range(8))) or type(value) is not int or not 0 <= value <= 65535:
                raise ValueError('invalid register expectation')
        if 'ppm_sha256' in test:
            import re
            if not isinstance(test['ppm_sha256'], str) or not re.fullmatch('[0-9a-f]{64}', test['ppm_sha256']):
                raise ValueError('invalid PPM digest')
    return manifest, files

def create(root, language):
    if root.exists():
        raise ValueError('project already exists')
    root.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=root.parent) as temporary:
        stage = Path(temporary)/'project'
        stage.mkdir()
        name = 'main.n16c' if language == 'n16c' else 'main.asm'
        (stage/name).write_text('fn main()->u16 { return 42; }\n' if language == 'n16c' else '.entry start\nstart: LDI R0, 42\nHALT\n')
        (stage/'n16-project.json').write_bytes(json_bytes(dict(schema_version=1, name=root.name[:64], language=language, entry=name, files=[name], tests=[dict(frames=1, registers={'0':42}, halted=True)])))
        stage.rename(root)

def build(root, bins):
    manifest, files = load(root)
    out = root/'.n16'
    if out.is_symlink() or (out.exists() and not out.is_dir()):
        raise ValueError('invalid build directory')
    with tempfile.TemporaryDirectory(prefix='n16-build-') as temporary:
        stage = Path(temporary)
        source = stage/'src'
        source.mkdir()
        for name, data in files.items():
            path = source/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        args = [source/manifest['entry'], '--out', stage/'program.n16', '--debug-symbols', stage/'program.map.json']
        if manifest['language'] == 'n16c':
            args += ['--assembly', stage/'program.asm', '--layout', stage/'layout.json']
            compiler = tool(bins, 'n16c')
        else:
            args += ['--project-root', source]
            compiler = tool(bins, 'n16asm')
        try:
            execute(compiler, *args, capture=True)
        except subprocess.CalledProcessError as failure:
            failure.stderr = failure.stderr.replace(str(source), str(root))
            raise
        outputs = {p.name:p.read_bytes() for p in stage.iterdir() if p.is_file()}
        outputs['build.json'] = json_bytes(dict(schema_version=1, compiler=execute(compiler, '--version', capture=True).stdout.strip(), sources={name:hashlib.sha256(data).hexdigest() for name,data in files.items()}, rom_bytes=len(outputs['program.n16'])-32))
        out.mkdir(exist_ok=True)
        # Stage every output before publication; callers never execute a failed build.
        for name in outputs:
            if (out/name).is_symlink() or ((out/name).exists() and not (out/name).is_file()):
                raise ValueError('invalid build output')
        for name, data in outputs.items():
            fd, path = tempfile.mkstemp(dir=out, prefix='.stage-')
            try:
                with os.fdopen(fd, 'wb') as stream:
                    stream.write(data)
                os.replace(path, out/name)
            finally:
                Path(path).unlink(missing_ok=True)
    return manifest, files, outputs

def test_project(root, bins, manifest):
    with tempfile.TemporaryDirectory() as temporary:
        image = Path(temporary)/'screen.ppm'
        for index, test in enumerate(manifest['tests']):
            args = ['run', root/'.n16/program.n16', '--headless', '--frames', test['frames'], '--screenshot', image]
            if 'input' in test:
                args += ['--input', root/test['input']]
            state = json.loads(execute(tool(bins, 'nova16'), *args, capture=True).stdout)
            if state['trapped']:
                raise AssertionError(f'test {index}: CPU trapped: {state}')
            for reg,value in test.get('registers', {}).items():
                if state['registers'][int(reg)] != value:
                    raise AssertionError(f'test {index}: R{reg} != {value}')
            if 'halted' in test and state['halted'] != test['halted']:
                raise AssertionError(f'test {index}: halted mismatch')
            if 'ppm_sha256' in test and hashlib.sha256(image.read_bytes()).hexdigest() != test['ppm_sha256']:
                raise AssertionError(f'test {index}: framebuffer mismatch')
            print(f'test {index}: passed')

def package(root, destination, manifest, files, outputs):
    destination = destination.resolve()
    if destination == root/'n16-project.json' or destination.is_relative_to(root/'.n16') or any(destination == (root/name).resolve() for name in files):
        raise ValueError('package aliases project input/build')
    archive_files = dict(files)
    archive_files['n16-project.json'] = json_bytes(manifest)
    archive_files.update({'.n16/'+name:data for name,data in outputs.items()})
    archive_files['package-manifest.json'] = json_bytes(dict(schema_version=1, files={name:hashlib.sha256(data).hexdigest() for name,data in sorted(archive_files.items())}))
    fd, staged = tempfile.mkstemp(dir=destination.parent, prefix='.n16-package-')
    os.close(fd)
    try:
        with zipfile.ZipFile(staged, 'w') as archive:
            for name, data in sorted(archive_files.items()):
                info = zipfile.ZipInfo(name, date_time=(1980,1,1,0,0,0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, data)
        os.replace(staged, destination)
    finally:
        Path(staged).unlink(missing_ok=True)
    print(destination)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bin-dir', type=Path, default=(Path(__file__).resolve().parents[1]/'zig-out/bin' if (Path(__file__).resolve().parents[1]/'zig-out/bin').exists() else Path(__file__).resolve().parents[1]/'bin'))
    commands = parser.add_subparsers(dest='command', required=True)
    for command in ('new', 'build', 'test', 'run', 'debug', 'pack'):
        sub = commands.add_parser(command)
        sub.add_argument('root', type=Path)
        if command == 'new':
            sub.add_argument('--language', choices=('asm', 'n16c'), default='n16c')
        if command == 'pack':
            sub.add_argument('--out', required=True, type=Path)
        if command in ('run', 'debug'):
            sub.add_argument('extra', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    root, bins = args.root.resolve(), args.bin_dir.resolve()
    if args.command == 'new':
        create(root, args.language)
        return
    manifest, files, outputs = build(root, bins)
    if args.command in ('test', 'pack'):
        test_project(root, bins, manifest)
    if args.command == 'pack':
        package(root, args.out, manifest, files, outputs)
    elif args.command in ('run', 'debug'):
        extra = args.extra[1:] if args.extra[:1] == ['--'] else args.extra
        if args.command == 'run':
            execute(tool(bins, 'nova16'), 'run', root/'.n16/program.n16', *extra)
        else:
            execute(tool(bins, 'n16dbg'), root/'.n16/program.n16', '--symbols', root/'.n16/program.map.json', *extra)
    elif args.command == 'build':
        print((root/'.n16/build.json').read_text(), end='')

if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as failure:
        if failure.stderr:
            print(failure.stderr, end='', file=__import__('sys').stderr)
        raise SystemExit(failure.returncode)
    except (ValueError, AssertionError, OSError, RecursionError) as failure:
        raise SystemExit(str(failure))

"""Distribute a local guest project with reproducible sources and compiled ROM."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import tempfile
import zipfile

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('root', type=pathlib.Path)
    ap.add_argument('--entry', default='main.asm')
    ap.add_argument('--out', required=True, type=pathlib.Path)
    ap.add_argument('--assembler', default='zig-out/bin/n16asm')
    args = ap.parse_args()
    root = args.root.resolve()
    entry = (root/args.entry).resolve()
    if not entry.is_relative_to(root):
        raise ValueError('entry outside project')
    with tempfile.TemporaryDirectory() as directory:
        temp = pathlib.Path(directory)
        rom, symbols = temp/'program.n16', temp/'program.sym2'
        subprocess.run([args.assembler, str(entry), '--project-root', str(root), '--out', str(rom), '--debug-symbols', str(symbols)], check=True, timeout=30)
        files = {'program.n16': rom.read_bytes(), 'program.sym2': symbols.read_bytes()}
        for path in sorted(root.rglob('*.asm')):
            if path.is_symlink() or not path.resolve().is_relative_to(root):
                raise ValueError('non-local source')
            files['src/'+path.relative_to(root).as_posix()] = path.read_bytes()
        manifest = {'schema_version': 1, 'entry': args.entry, 'isa_version': 1, 'rom_version': 1,
                    'files': {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())}}
        files['guest-manifest.json'] = (json.dumps(manifest, indent=2, sort_keys=True)+'\n').encode()
        # Stage archive beside output, then replace. No partial successful package.
        import os
        fd, staged = tempfile.mkstemp(dir=args.out.resolve().parent, prefix='.n16-guest-')
        os.close(fd)
        try:
            with zipfile.ZipFile(staged, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
                for name, data in sorted(files.items()):
                    info = zipfile.ZipInfo(name, date_time=(1980,1,1,0,0,0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = 0o100644 << 16
                    archive.writestr(info, data)
            os.replace(staged, args.out)
        finally:
            pathlib.Path(staged).unlink(missing_ok=True)
    print(args.out)
if __name__ == '__main__':
    main()

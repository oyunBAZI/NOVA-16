"""Repackage after generated project caches exist; require exact SDK ZIP bytes."""
import hashlib,pathlib,subprocess,sys,zipfile
root=pathlib.Path(__file__).resolve().parents[1]
archives=list((root/'dist').glob('nova16-*.zip'))
assert len(archives)==1,'use a clean dist directory for the native SDK gate'
archive=archives[0];first=hashlib.sha256(archive.read_bytes()).hexdigest()
with zipfile.ZipFile(archive) as package:
 assert all('/.n16/' not in name for name in package.namelist()),'build cache in SDK sources'
subprocess.run([sys.executable,str(root/'scripts/package.py')],cwd=root,check=True,timeout=180)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==first,'SDK archive changed after cached project rebuilds'
print('Native SDK exact-byte reproducibility after project rebuilds passed')

"""Exercise both project languages, isolated dependencies and distributable rebuilds."""
import hashlib,json,pathlib,subprocess,sys,tempfile,zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
TOOL=ROOT/'scripts/n16.py'
def run(*args,ok=True,stdin=None):
 p=subprocess.run([sys.executable,str(TOOL),'--bin-dir',str(ROOT/'zig-out/bin' if (ROOT/'zig-out/bin').exists() else ROOT/'bin'),*map(str,args)],capture_output=True,text=True,input=stdin,timeout=90)
 assert (p.returncode==0)==ok,(p.args,p.stdout,p.stderr)
 return p
with tempfile.TemporaryDirectory() as temp:
 root=pathlib.Path(temp)
 for language in ('asm','n16c'):
  project=root/language
  run('new',project,'--language',language)
  run('test',project)
  assert '42' in run('run',project,'--','--headless','--frames','1').stdout
  debug=run('debug',project,stdin='symbols\ncontinue\nregs\nquit\n')
  assert 'R0=002a' in debug.stdout
  if language=='asm':
   (project/'main.asm').write_text('.include "body.inc"\n')
   (project/'body.inc').write_text('LDI R0,42\nHALT\n')
   # Undeclared dependencies are not visible to the build.
   run('build',project,ok=False)
   manifest=json.loads((project/'n16-project.json').read_text())
   manifest['files'].append('body.inc')
   (project/'n16-project.json').write_text(json.dumps(manifest))
  run('pack',project,'--out',root/'one.zip')
  run('pack',project,'--out',root/'two.zip')
  assert (root/'one.zip').read_bytes()==(root/'two.zip').read_bytes()
  with zipfile.ZipFile(root/'one.zip') as archive:
   digests=json.loads(archive.read('package-manifest.json'))['files']
   assert all(hashlib.sha256(archive.read(name)).hexdigest()==digest for name,digest in digests.items())
   restored=root/(language+'-unpacked');archive.extractall(restored)
  run('test',restored)
  run('pack',project,'--out',project/'n16-project.json',ok=False)
  old=(project/'.n16/program.n16').read_bytes()
  manifest=json.loads((project/'n16-project.json').read_text())
  (project/manifest['entry']).write_text('invalid code')
  run('run',project,'--','--frames','1',ok=False)
  assert (project/'.n16/program.n16').read_bytes()==old
  manifest['files']=['../outside.asm'];manifest['entry']='../outside.asm'
  (project/'n16-project.json').write_text(json.dumps(manifest))
  run('build',project,ok=False)
 # Adversarial manifests reject deterministically without executing retained ROMs.
 project=root/'manifest-adversaries';run('new',project)
 good=json.loads((project/'n16-project.json').read_text())
 for change in ({'files':['']},{'files':[{}]},{'entry':[]},{'schema_version':True},{'files':['main.n16c','MAIN.n16c']},{'tests':[{'frames':1,'input':[]}]}):
  (project/'n16-project.json').write_text(json.dumps(good|change))
  failure=run('build',project,ok=False)
  assert 'Traceback' not in failure.stderr
print('Projects: create/build/run/debug/test, isolated includes, deterministic packages/rebuild, failed-build retention passed')

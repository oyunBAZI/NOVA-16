"""Native compiler CLI integrity and V1 execution acceptance."""
import pathlib,subprocess,tempfile,json
ROOT=pathlib.Path(__file__).resolve().parents[1]
BIN=ROOT/'zig-out/bin'
def run(exe,*args,ok=True,stdin=None):
 p=subprocess.run([str(BIN/exe),*map(str,args)],input=stdin,text=True,capture_output=True,timeout=30)
 assert (p.returncode==0)==ok,(p.args,p.stdout,p.stderr)
 return p
with tempfile.TemporaryDirectory() as directory:
 p=pathlib.Path(directory);rom=p/'program.n16';source=p/'main.n16c';asm=p/'program.asm';symbols=p/'program.sym2';layout=p/'layout.json'
 source.write_text((ROOT/'examples/typed/demo.n16c').read_text())
 run('n16c',source,'--out',rom,'--assembly',asm,'--debug-symbols',symbols,'--layout',layout)
 first=rom.read_bytes()
 assert len(first)<=8224 and json.loads(layout.read_text())['abi_version']==1
 rebuilt=p/'rebuilt.n16'
 run('n16asm',asm,'--out',rebuilt)
 assert rebuilt.read_bytes()==first
 state=json.loads(run('nova16','run',rom,'--frames','120').stdout)
 assert state['halted'] and not state['trapped'] and state['registers'][0]==42
 session=run('n16dbg',rom,'--symbols',symbols,stdin='break main.n16c:8\ncontinue 100\nsource\nnext\nregs\nquit\n').stdout
 assert 'breakpoint before' in session and 'main.n16c:8:' in session
 source.write_text('fn main()->u16 { return true; }')
 error=json.loads(run('n16c',source,'--out',rom,'--diagnostics','json',ok=False).stderr)
 assert error['code']=='TypeMismatch' and error['line']==1
 assert rom.read_bytes()==first
print('Compiler CLI: real V1 ROM, ordinary assembly reassembly, source map/debugger, limits and artifact retention passed')

"""Native compiler CLI integrity and V1 execution acceptance."""
import pathlib,subprocess,tempfile,json
ROOT=pathlib.Path(__file__).resolve().parents[1]
BIN=(ROOT/'zig-out/bin' if (ROOT/'zig-out/bin').exists() else ROOT/'bin')
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
 # Schema3 retains original source and frame-relative locals through snapshot/reverse.
 assert json.loads(symbols.read_text())['schema_version']==3
 source.write_text('var global:u16=7;\nfn main()->u16 {\n var local:i16=i16(65535);\n global=42;\n return global+u16(local);\n}\n')
 run('n16c',source,'--out',rom,'--debug-symbols',symbols)
 session=run('n16dbg',rom,'--symbols',symbols,stdin=f'break main.n16c:4\ncontinue 1000\nvars\nhistory 32\nnext\nvars\nsavesnap {p/"debug.n16s"}\nstep\nreverse\nvars\nloadsnap {p/"debug.n16s"}\nvar local\nquit\n').stdout
 assert 'global:u16=7' in session and 'global:u16=42' in session and 'local:i16=-1' in session,session
 source.write_text('var divisor:u16;\nfn main()->u16 {\n return 7/divisor;\n}\n')
 run('n16c',source,'--out',rom,'--debug-symbols',symbols)
 session=run('n16dbg',rom,'--symbols',symbols,stdin='continue 10000\nregs\nquit\n').stdout
 assert 'guest error 2 at main.n16c:3' in session,session
 # Architectural traps also resolve to typed source.
 source.write_text('fn main()->u16 {\n return peek16(55552);\n}\n')
 run('n16c',source,'--out',rom,'--debug-symbols',symbols)
 session=run('n16dbg',rom,'--symbols',symbols,stdin='continue 1000\nregs\nquit\n').stdout
 assert 'trap' in session and 'main.n16c:2:' in session,session
 # Restore the successful artifact for failed-build atomicity check below.
 first=rom.read_bytes()
 source.write_text('fn main()->u16 { return true; }')
 error=json.loads(run('n16c',source,'--out',rom,'--diagnostics','json',ok=False).stderr)
 assert error['code']=='TypeMismatch' and error['line']==1
 assert rom.read_bytes()==first
print('Compiler CLI: real V1 ROM, ordinary assembly reassembly, source map/debugger, limits and artifact retention passed')

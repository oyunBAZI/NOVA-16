"""Real guest application ROM/replay/source-state/packaging acceptance."""
import hashlib,json,pathlib,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1];BIN=(ROOT/'zig-out/bin' if (ROOT/'zig-out/bin').exists() else ROOT/'bin')
DEMOS=ROOT/'zig-out/demos' if (ROOT/'zig-out/demos').exists() else ROOT/'demos'
CASES=[('crates','title',30,{},None),('crates','win',460,{'state':4,'level':2,'moves':7},'win'),('crates','undo',100,{'player':13,'moves':0,'state':1},'undo'),('crates','collision',90,{'player':13,'moves':0},'collision'),('crates','restart',100,{'player':13,'moves':0,'level':0},'restart'),('crates','blocked',180,{'state':3},'blocked'),('pixel_studio','blank',30,{'edits':0},None),('pixel_studio','drawing',180,{'edits':6,'cursor':19,'ink':13},'drawing'),('pixel_studio','undo',100,{'edits':3,'undo_valid':0},'undo'),('pixel_studio','clear',120,{'edits':0,'confirm_clear':0},'clear')]
def run(name,*args,stdin=None):
 p=subprocess.run([str(BIN/name),*map(str,args)],input=stdin,capture_output=True,text=True,timeout=60)
 assert p.returncode==0,(p.args,p.stdout[-2000:],p.stderr)
 return p.stdout
with tempfile.TemporaryDirectory() as temporary:
 temp=pathlib.Path(temporary);goldens=json.loads((ROOT/'docs/apps/hashes.json').read_text())
 for app in ('crates','pixel_studio'):
  rom=temp/(app+'.n16');source=ROOT/f'examples/projects/{app}/main.n16c'
  run('n16c',source,'--out',rom)
  assert rom.read_bytes()==(DEMOS/f'{app}.n16').read_bytes()
  assert len(rom.read_bytes())<=8224
 for app,scene,frames,expected,replay in CASES:
  rom=DEMOS/f'{app}.n16';symbols=DEMOS/f'{app}.map.json'
  args=['run',rom,'--headless','--frames',frames,'--screenshot',temp/'frame.ppm']
  commands=[];current=0
  if replay:
   schedule=ROOT/f'examples/projects/{app}/{replay}.input';args+=['--input',schedule]
   for line in schedule.read_text().splitlines():
    frame,mask=map(int,line.split())
    if frame>current:commands.append(f'frame {frame-current}')
    commands.append(f'input {mask}');current=frame
  if frames>current:commands.append(f'frame {frames-current}')
  commands+=['vars','regs',f'savesnap {temp/"state.n16s"}','quit']
  state=json.loads(run('nova16',*args));assert not state['trapped'] and not state['halted']
  digest=hashlib.sha256((temp/'frame.ppm').read_bytes()).hexdigest()
  assert digest==goldens[app+'-'+scene],(app,scene,digest)
  output=run('n16dbg',rom,'--symbols',symbols,stdin='\n'.join(commands)+'\n')
  mapping=json.loads(symbols.read_text())
  snapshot=(temp/'state.n16s').read_bytes()
  ram=snapshot[32+128:32+128+65536]
  for name,value in expected.items():
   variable=next(v for v in mapping['variables'] if v['name']==name and not v['frame_relative'])
   got=int.from_bytes(ram[variable['address']:variable['address']+2],'little')
   assert got==value,(app,scene,name,value,got)
  if app=='pixel_studio':
   canvas=list(int.from_bytes(ram[256+i*2:258+i*2],'little') for i in range(192))
   if scene=='drawing':assert [canvas[i] for i in (0,1,2,18,19)]==[12,12,12,13,13]
   if scene=='clear':assert canvas==[0]*192
   if scene=='undo':assert canvas[:2]==[12,0]
  print(f'{app}/{scene}: real ROM, framebuffer SHA and guest state passed')
print('All application replays passed')

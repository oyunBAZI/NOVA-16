"""Independent profile2 SPECIFICATION fixtures; never implements VM hardware."""
import base64,hashlib,json,pathlib,struct,subprocess,sys,tempfile,zlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
def put(out,offset,fmt,*values):struct.pack_into('<'+fmt,out,offset,*values)
def crc(data):return zlib.crc32(data)&0xffffffff
def bundle(data):return dict(base64=base64.b64encode(data).decode(),sha256=hashlib.sha256(data).hexdigest(),bytes=len(data))
def trunc(value,denominator):return (abs(value)//denominator)*(-1 if value<0 else 1)
def pcm(count):
 phase=0;noise=0xace2;out=[]
 for _ in range(count):
  square=32767 if phase<0x80000000 else -32767
  saw=(phase>>16)-32768
  high=phase>>16;triangle=2*high-32768 if high<32768 else 98303-2*high
  bit=((noise>>0)^(noise>>2)^(noise>>3)^(noise>>5))&1;noise=(noise>>1)|(bit<<15)
  noise_value=32767 if noise&1 else -32767
  total=square+trunc(saw*127,255)+trunc(triangle*200,255)+trunc(noise_value*64,255)
  out.append(trunc(trunc(total,4)*193,255));phase=(phase+0x40000000)&0xffffffff
 return out

def make():
 payload=b'\x01\x00';header=bytearray(32);header[:4]=b'N16R';put(header,4,'HHHHIHH',2,0,2,0,crc(payload),2,3);rom=header+payload
 def snapshot(slots):
  cpu=bytearray(160);put(cpu,0,'I',crc(payload));cpu[7]=1;put(cpu,24,'HHH',0xe002,0xbffe,0);put(cpu,32,'Q',1);put(cpu,40,'iH',0xe000,1);cpu[59]=1;put(cpu,60,'H',(slots//20000)%65536);put(cpu,64,'H',2)
  put(cpu,128,'QQHHB',slots,0,slots%20000,(slots%20000)//25,slots%25)
  memory=bytearray(65584);memory[0xe000:0xe002]=payload
  # MEM1 palette is explicit grayscale here, a legal caller-edited V1 palette.
  memory[65536:]=bytes(v for i in range(16) for v in (i*17,)*3)
  audio=bytearray(1696);audio[0]=1;audio[1]=255;put(audio,8,'Q',slots//25)
  for i in range(4):put(audio,32+16*i,'IIHBBB',0x40000000 if i==0 else 0,((slots//25)*0x40000000)&0xffffffff if i==0 else 0,0xace1^i,255 if i==0 else 0,0,1 if i==0 else 0)
  for i in range((slots%20000)//25):put(audio,96+2*i,'h',8191 if i%4<2 else -8191)
  irq=bytearray(128);irq[0]=(2 if slots>=7 else 0) | (1 if slots>=20000 else 0);irq[1]=3;put(irq,4,'II',7,7-slots%7);irq[12]=1
  chunks=[(b'CPU2',cpu),(b'MEM1',memory),(b'AUD1',audio),(b'IRQ1',irq)]
  result=bytearray(67680);result[:4]=b'N16S';put(result,4,'HHI',2,0,len(result));put(result,16,'HHI',2,4,32)
  offset=112
  for i,(tag,data) in enumerate(chunks):
   struct.pack_into('<4sIIII',result,32+i*20,tag,offset,len(data),crc(data),0);result[offset:offset+len(data)]=data;offset+=len(data)
  assert offset==len(result);put(result,12,'I',crc(result[32:]));return result
 samples=pcm(800)
 timer=[];remaining=3;pending=0
 for slot in range(1,9):
  remaining-=1
  if remaining==0:pending|=2;remaining=3
  if slot==5:pending&=~2
  timer.append(dict(slot=slot,remaining=remaining,pending=pending))
 # Descending push PC, flags, IE. Snapshot return top points at IE.
 entry=struct.pack('<HHH',1,5,0xe012)
 fixtures=dict(schema_version=1,contract_revision=2,rom2_halt=bundle(rom),snapshot2_idle137=bundle(snapshot(137)),snapshot2_boundary20000=bundle(snapshot(20000)),pcm=dict(samples_first32=samples[:32],sha256=hashlib.sha256(struct.pack('<800h',*samples)).hexdigest(),configuration=dict(step=0x40000000,volumes=[255,127,200,64],waves=[0,1,2,3],phases=[0,0,0,0],noise_seed=0xace2,gain=193)),timer_period3_reload=timer,irq_entry=dict(old_pc=0xe012,flags=5,old_ie=1,sp_before=0xbffe,sp_after=0xbff8,stack_top_six_hex=entry.hex(),selected_vector=0,pending_before=3,pending_after=2,iret=dict(pc=0xe012,flags=5,ie=1,sp=0xbffe)),atomic_rejects=[dict(write_address=0xd906,width=2,reason='WriteDenied',control_before=0,control_after=0),dict(write_address=0xd902,width=2,value=0x8001,reason='DeviceValue',step_before=0,step_after=0),dict(instruction='IRET',sp=0xbff6,frame_top=0xbff8,reason='InvalidInterruptState',state_unchanged=True)])
 zig='// Generated independently by scripts/v2_contract_vectors.py; specification math only.\npub const first = [_]i16{'+','.join(map(str,samples[:32]))+'};\npub const sha256 = [_]u8{'+','.join(map(str,bytes.fromhex(fixtures['pcm']['sha256'])))+'};\n'
 return fixtures,zig

def main():
 fixtures,zig=make();path=ROOT/'docs/vectors/v2-contract.json';zpath=ROOT/'src/experimental/audio_vectors.zig'
 if '--write' in sys.argv:
  path.parent.mkdir(exist_ok=True);path.write_text(json.dumps(fixtures,sort_keys=True,indent=2)+'\n');zpath.write_text(zig)
 else:
  assert json.loads(path.read_text())==fixtures,'V2 fixture drift'
  # Compare parsed generated constants, formatting may be normalized by Zig.
  import re
  numbers=lambda text:list(map(int,re.findall(r'(?<![A-Za-z0-9_])\d+',text[text.index('pub const first'):])) )
  assert numbers(zpath.read_text())==numbers(zig),'V2 Zig arithmetic fixture drift'
  with tempfile.TemporaryDirectory() as temp:
   directory=pathlib.Path(temp);rom=directory/'v2.n16';snap=directory/'v2.n16s';rom.write_bytes(base64.b64decode(fixtures['rom2_halt']['base64']));snap.write_bytes(base64.b64decode(fixtures['snapshot2_idle137']['base64']))
   bins=ROOT/'zig-out/bin' if (ROOT/'zig-out/bin').exists() else ROOT/'bin';suffix='.exe' if sys.platform=='win32' else ''
   denied=subprocess.run([str(bins/('nova16'+suffix)),'inspect',str(rom)],capture_output=True,text=True,timeout=30);assert denied.returncode!=0 and 'BadVersion' in denied.stderr
   session=subprocess.run([str(bins/('n16dbg'+suffix)),str((ROOT/'zig-out/demos' if (ROOT/'zig-out/demos').exists() else ROOT/'demos')/'diagnostics.n16')],input=f'step 2\nregs\nloadsnap {snap}\nregs\nquit\n',capture_output=True,text=True,timeout=30)
   assert session.returncode==0 and 'StreamTooLong' in session.stdout
   pcs=re.findall(r'PC=.* SP=.*',session.stdout);assert len(pcs)==2 and pcs[0]==pcs[1]
  print('V2 specification vectors, independent audio math, and shipping V1 atomic rejection passed (no V2 hardware)')
if __name__=='__main__':main()

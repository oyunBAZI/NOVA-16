import pathlib,subprocess,tempfile,time,json,statistics
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d); rows=[]
 for n in (256,512,1024):
  src=''.join(f'.equ s{i}, s{i+1} + 1\n' for i in range(n))+f'.equ s{n}, 0\nLDI R0, s0\nHALT\n'
  (p/'bench.asm').write_text(src); times=[]
  for _ in range(3):
   t=time.perf_counter();subprocess.run(['zig-out/bin/n16asm',str(p/'bench.asm'),'--out',str(p/'bench.n16')],check=True,capture_output=True);times.append(time.perf_counter()-t)
  rows.append({'symbols':n+1,'seconds':times,'median_seconds':statistics.median(times)})
 print(json.dumps(rows,indent=2))

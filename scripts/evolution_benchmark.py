"""Compare real guest/compiler workloads with a specified baseline checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline',type=Path,required=True)
p.add_argument('--out',type=Path,default=ROOT/'zig-out/evolution-benchmark.json')
a=p.parse_args();baseline=a.baseline.resolve()

def run(binary,*args):
    p=subprocess.run([str(binary),*map(str,args)],capture_output=True,text=True,timeout=60)
    if p.returncode:raise RuntimeError(p.stderr)
    return p.stdout

suffix='.exe' if __import__('os').name=='nt' else ''
new=ROOT/'zig-out/bin';old=baseline/'zig-out/bin'
report={'schema_version':1,'baseline_commit':run('git','-C',baseline,'rev-parse','HEAD').strip(),
        'current_commit':run('git','-C',ROOT,'rev-parse','HEAD').strip(),
        'source_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ('src/compiler/compiler.zig','guest/lib/graphics.asm','src/debug/history.zig','src/debug/timeline.zig')},
        'compiler':{},'graphics':{},'limits':'Same-host fresh-process medians include loading, output and OS noise. Guest instruction counts isolate software changes; no hardware/CPU speedup is implied.'}
with tempfile.TemporaryDirectory() as directory:
    directory=Path(directory)
    for app in ('crates','pixel_studio'):
        source=ROOT/'examples/projects'/app/'main.n16c'
        entry={}
        for label,bins in (('baseline',old),('optimized',new)):
            output=directory/(app+label+'.n16');elapsed=[]
            for _ in range(7):
                start=time.perf_counter_ns();run(bins/('n16c'+suffix),source,'--out',output);elapsed.append(time.perf_counter_ns()-start)
            entry[label]={'payload_bytes':output.stat().st_size-32,'compile_ns':elapsed,'median_compile_ns':statistics.median(elapsed)}
        report['compiler'][app]=entry
    libraries={'baseline':(baseline/'guest/lib/graphics.asm').read_text(encoding='utf-8'),'packed':(ROOT/'guest/lib/graphics.asm').read_text(encoding='utf-8')}
    for name,setup in [('clear','LDI R0,9\nCALL n16_clear'),('full_rect','LDI R0,9\nCALL n16_color\nLDI R0,0\nLDI R1,0\nLDI R2,128\nLDI R3,96\nCALL n16_rect'),('odd_clipped_rect','LDI R0,9\nCALL n16_color\nLDI R0,31\nLDI R1,17\nLDI R2,65535\nLDI R3,65535\nCALL n16_rect')]:
        entry={};digest=None
        for label,library in libraries.items():
            source=directory/(name+label+'.asm');image=directory/(name+label+'.n16');ppm=directory/(name+label+'.ppm')
            source.write_text('.entry start\nstart: '+setup+'\nHALT\n'+library,encoding='utf-8')
            run(new/('n16asm'+suffix),source,'--out',image)
            elapsed=[]
            for _ in range(7):
                start=time.perf_counter_ns();state=json.loads(run(new/('nova16'+suffix),'run',image,'--frames','100','--max-instructions','2000000','--screenshot',ppm));elapsed.append(time.perf_counter_ns()-start)
            assert state['halted'] and not state['trapped']
            actual=hashlib.sha256(ppm.read_bytes()).hexdigest()
            if digest:assert actual==digest
            digest=actual
            entry[label]={'retired_instructions':state['executed_instructions'],'payload_bytes':image.stat().st_size-32,'ppm_sha256':actual,'run_ns':elapsed,'median_run_ns':statistics.median(elapsed)}
        report['graphics'][name]=entry
    for app in ('nova_tracker','starfall'):
        source=ROOT/'examples/projects'/app/'main.n16c';output=directory/(app+'.n16')
        baseline_process=subprocess.run([str(old/('n16c'+suffix)),str(source),'--out',str(output)],capture_output=True,text=True,timeout=60)
        report['compiler'][app]={'baseline_compiles':baseline_process.returncode==0,'baseline_diagnostic':baseline_process.stderr.strip(),'optimized_payload_bytes':(ROOT/'zig-out/demos'/(app+'.n16')).stat().st_size-32}
a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'compiler':report['compiler'],'graphics':{name:{mode:value['retired_instructions'] for mode,value in case.items()} for name,case in report['graphics'].items()}},indent=2))

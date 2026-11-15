"""Run reproducible native/portable/package gates and retain exact command evidence."""
import argparse
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--zig',default=os.environ.get('NOVA_ZIG','zig'))
p.add_argument('--node',default=os.environ.get('NOVA_NODE','node'))
p.add_argument('--mode',choices=('Debug','ReleaseSafe','both'),default='both')
p.add_argument('--cross',action='store_true')
p.add_argument('--portable',action='store_true')
p.add_argument('--package',action='store_true')
p.add_argument('--browser',action='store_true',help='Require actual browser acceptance (development dependencies needed)')
p.add_argument('--browser-executable',help='Use this Chromium executable for --browser')
p.add_argument('--out',type=Path,default=ROOT/'zig-out/validation.json')
a=p.parse_args()
if a.package and a.mode=='Debug':p.error('--package requires ReleaseSafe or both')
if a.browser_executable and not a.browser:p.error('--browser-executable requires --browser')
environment=os.environ.copy()
zig=shutil.which(a.zig)
if not zig:raise SystemExit('Zig 0.17.1 required; use --zig PATH')
environment['PATH']=str(Path(zig).parent)+os.pathsep+environment['PATH']
node=shutil.which(a.node)
if a.portable and not node:raise SystemExit('Node required for --portable; use --node PATH')
if node:environment['NOVA_NODE']=node
report={'schema_version':1,'started_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'checks':[],'passed':False}
def source_hashes():
    paths=subprocess.check_output(['git','ls-files','-co','--exclude-standard','--','src','guest','examples','scripts','workbench','wasm','build.zig','build.zig.zon','.github/workflows','.gitattributes','docs/vectors/source.zig','docs/quality/replay-cases.json'],cwd=ROOT,text=True).splitlines()
    return {name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sorted(set(paths)) if (ROOT/name).is_file()}
source_paths=list(source_hashes())
report['source_dirty']=bool(subprocess.check_output(['git','status','--porcelain','--',*source_paths],cwd=ROOT,text=True).strip())
report['source_sha256']=source_hashes()
a.out.parent.mkdir(parents=True,exist_ok=True)
def save():
    temporary=a.out.with_name(a.out.name+'.tmp')
    temporary.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');temporary.replace(a.out)
def check(*command,timeout=600):
    print('Running: '+' '.join(map(str,command)),flush=True)
    entry={'command':list(map(str,command)),'status':'running','timeout_seconds':timeout}
    report['checks'].append(entry);save();start=time.monotonic()
    try:
        r=subprocess.run(list(map(str,command)),cwd=ROOT,env=environment,capture_output=True,text=True,timeout=timeout)
        entry.update(exit_code=r.returncode,output=(r.stdout+r.stderr)[-16000:])
    except subprocess.TimeoutExpired as error:
        def decode(value):return value.decode('utf-8',errors='replace') if isinstance(value,bytes) else value or ''
        entry.update(exit_code=124,timed_out=True,output=(decode(error.stdout)+decode(error.stderr))[-16000:])
    entry.update(status='passed' if entry['exit_code']==0 else 'failed',seconds=round(time.monotonic()-start,3));save()
    if entry['exit_code']:print(entry['output']);raise SystemExit(entry['exit_code'])
check(zig,'build','fmt')
scripts=('acceptance','compatibility_acceptance','developer_acceptance','compiler_acceptance','project_acceptance','application_acceptance','v2_contract_vectors','v2_acceptance','game_acceptance','workbench_acceptance','evolution_acceptance','security_check','project_stress')
for mode in ('Debug','ReleaseSafe') if a.mode=='both' else (a.mode,):
    check(zig,'build','-Doptimize='+mode)
    check(zig,'build','test','-Doptimize='+mode,'--summary','all','--test-timeout','2m')
    check(zig,'build','v2-model-test','-Doptimize='+mode,'--summary','all')
    for script in scripts:check(sys.executable,'scripts/'+script+'.py')
if a.portable:
    check(node,'scripts/wasm_acceptance.mjs')
    check(sys.executable,'scripts/package_web.py')
    check(node,'scripts/offline_acceptance.mjs')
    check(node,'scripts/offline_worker_acceptance.mjs')
    check(node,'scripts/frontend_acceptance.mjs')
    check(node,'scripts/session_soak.mjs','--cycles','20','--seconds','0','--out',ROOT/'zig-out/session-soak.json')
if a.cross:check(sys.executable,'scripts/cross_acceptance.py',timeout=1200)
if a.browser:
    if not a.portable:check(sys.executable,'scripts/package_web.py')
    command=[sys.executable,'scripts/browser_acceptance.py']
    if a.browser_executable:command+=['--executable',a.browser_executable]
    check(*command)
if a.package:
    check(sys.executable,'scripts/package.py')
    check(sys.executable,'scripts/package_reproducibility.py')
    for package in sorted((ROOT/'dist').glob('*.zip')):
        check(sys.executable,'scripts/verify_package.py',package,timeout=600)
report['source_changed_during_validation']=report['source_sha256']!=source_hashes()
report['completed_utc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
report['passed']=not report['source_changed_during_validation'];save()
if not report['passed']:raise SystemExit('Source changed during validation; rerun against a stable tree')
print('All',len(report['checks']),'validation gates passed; evidence:',a.out)

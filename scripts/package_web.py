"""Export a self-contained offline Workbench; no CDN, fetch, Python or server at runtime."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import workbench as w

def package(destination):
    destination=Path(destination)
    wasm=ROOT/('zig-out/wasm/nova16.wasm' if (ROOT/'zig-out/wasm/nova16.wasm').is_file() else 'wasm/nova16.wasm')
    data={'schema_version':1,'wasm':base64.b64encode(wasm.read_bytes()).decode(),
          'editor_source':(ROOT/'examples/typed/demo.n16c').read_text(encoding='utf-8'),'cartridges':{}}
    for name,title in w.DEMO_NAMES.items():
        symbols=next((p for p in (w.DEMOS/(name+'.map.json'),w.DEMOS/(name+'.sym2'),w.DEMOS/(name+'.sym')) if p.is_file()),None)
        card={'title':title,'rom':base64.b64encode((w.DEMOS/(name+'.n16')).read_bytes()).decode(),'symbols':symbols.read_text(encoding='utf-8') if symbols else None}
        if name in w.TYPED_DEMOS:
            card.update(source=(ROOT/'examples/projects'/name/'main.n16c').read_text(encoding='utf-8'),architecture=w.TYPED_DEMOS[name])
        data['cartridges'][name]=card
    adapter=(ROOT/'wasm/nova16.mjs').read_text(encoding='utf-8').replace('export class ','class ').replace('export async function ','async function ')
    host=(ROOT/'wasm/offline-host.mjs').read_text(encoding='utf-8')
    host=re.sub(r'^import .*?;\n','',host,flags=re.M).replace('export function ','function ')
    worker=adapter+'\n'+host+'''\nconst host=createOfflineHost(DATA);let serial=Promise.resolve();
self.onmessage=event=>{const {id,payload}=event.data;serial=serial.then(()=>host(payload)).then(response=>self.postMessage({id,response})).catch(error=>self.postMessage({id,response:{status:503,result:{error:error.message}}}));};
'''
    assets=json.dumps(data,separators=(',',':')).replace('<','\\u003c').replace('\u2028','\\u2028').replace('\u2029','\\u2029')
    initializer='''<script id="nova-assets" type="application/json">'''+assets+'''</script>
<script>
(() => {
  window.NovaOfflineRequest=()=>Promise.reject(Error('Offline VM initialization failed; this browser must support WebAssembly and Workers.'));
  const data=JSON.parse(document.getElementById('nova-assets').textContent);
  const code='const DATA='+JSON.stringify(data)+';\\n'+WORKER;
  const url=URL.createObjectURL(new Blob([code],{type:'text/javascript'}));
  let worker;try{worker=new Worker(url);}catch(error){URL.revokeObjectURL(url);throw error;}let next=0;const pending=new Map();
  worker.onmessage=event=>{URL.revokeObjectURL(url);const job=pending.get(event.data.id);if(job){pending.delete(event.data.id);const response=event.data.response;job.resolve({ok:response.status>=200&&response.status<300,json:async()=>response.result});}};
  worker.onerror=()=>{URL.revokeObjectURL(url);for(const job of pending.values())job.reject(Error('Offline VM Worker failed'));pending.clear();};
  window.NovaOfflineRequest=payload=>new Promise((resolve,reject)=>{const id=++next;pending.set(id,{resolve,reject});worker.postMessage({id,payload});});
  window.addEventListener('pagehide',()=>worker.terminate(),{once:true});
})();
</script>'''.replace('WORKER',json.dumps(worker).replace('<','\\u003c'))
    html=(ROOT/'workbench/index.html').read_text(encoding='utf-8')
    html=html.replace('<link rel="stylesheet" href="/style.css">','<style>'+(ROOT/'workbench/style.css').read_text(encoding='utf-8')+'</style>')
    html=html.replace('<script src="/app.js" defer></script>','')
    html=html.replace('<title>NOVA / 16 — Workbench</title>','<title>NOVA / 16 — Offline Workbench</title>')
    html=html.replace('href="/" aria-label="NOVA Workbench"','href="#" aria-label="NOVA Workbench"').replace('LOCAL MACHINE','OFFLINE / WASM')
    html=html.replace('Native machine connected through protocol v1.','Wasm machine connected through protocol v1.')
    script=(ROOT/'workbench/app.js').read_text(encoding='utf-8').replace('</script','<\\/script')
    html=html.replace('<head>', "<head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline' 'wasm-unsafe-eval'; style-src 'unsafe-inline'; worker-src blob:; connect-src 'none'; img-src data: blob:; base-uri 'none'; form-action 'none'\">")
    html=html.replace('</body>',initializer+'\n<script>'+script+'</script>\n</body>')
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_bytes(html.encode('utf-8'))
    print(json.dumps({'file':str(destination),'bytes':destination.stat().st_size,'sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),'roms':len(data['cartridges'])}))
    return data

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'zig-out/web/NOVA16-Offline-Workbench.html')
    args=parser.parse_args();package(args.out)

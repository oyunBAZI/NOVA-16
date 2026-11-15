/** Execute the export's exact launcher and generated Worker code in real Node
 * threads. This tests the transport/lifetime path, not browser rendering/CSP. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {Worker as NodeWorker} from 'node:worker_threads';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const filename=fs.existsSync(path.join(root,'zig-out/web/NOVA16-Offline-Workbench.html'))?'zig-out/web/NOVA16-Offline-Workbench.html':'web/NOVA16-Offline-Workbench.html';
const html=fs.readFileSync(path.join(root,filename),'utf8');
const assets=html.match(/<script id="nova-assets" type="application\/json">([\s\S]*?)<\/script>/)[1];
const scripts=[...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].filter(m=>!m[0].startsWith('<script id="nova-assets"')).map(m=>m[1]);
const urls=new Map();let thread;const errors=[];
class TestBlob { constructor(parts){this.code=parts.join('');} }
class TestWorker {
  constructor(url) {
    const code=urls.get(url);assert.equal(typeof code,'string');
    const shim=`const {parentPort}=require('node:worker_threads');globalThis.self=globalThis;self.postMessage=value=>parentPort.postMessage(value);parentPort.on('message',data=>self.onmessage({data}));\n`;
    this.worker=new NodeWorker(shim+code,{eval:true});thread=this.worker;
    this.worker.on('message',data=>this.onmessage?.({data}));
    this.worker.on('error',error=>{errors.push(error);this.onerror?.(error);});
  }
  postMessage(data){this.worker.postMessage(data);}
  terminate(){return this.worker.terminate();}
}
const window={addEventListener(){}};
const context=vm.createContext({window,document:{getElementById(id){assert.equal(id,'nova-assets');return {textContent:assets};}},
  Blob:TestBlob,Worker:TestWorker,URL:{createObjectURL(blob){const url='blob:test/'+urls.size;urls.set(url,blob.code);return url;},revokeObjectURL(url){urls.delete(url);}}});
new vm.Script(scripts[0]).runInContext(context);
let revision=0;
async function request(payload,status=200) {
  const response=await window.NovaOfflineRequest({...payload,revision});
  assert.equal(response.ok,status>=200&&status<300);
  const result=await response.json();if(Number.isInteger(result.revision))revision=result.revision;
  return result;
}
try {
  const initial=await request({op:'bootstrap'});
  assert.equal(Object.keys(initial.demos).length,11);assert.equal(initial.ok,true);
  // The actual Worker queue must reject the second stale mutation, even when
  // callers submit both messages concurrently outside the normal UI queue.
  const results=await Promise.all([1,2].map(mask=>window.NovaOfflineRequest({op:'vm',request:{op:'command',command:`input ${mask}`},revision})));
  assert.equal(results[0].ok,true);assert.equal(results[1].ok,false);
  revision=(await results[0].json()).revision;
  let result=await request({op:'build',source:'fn main()->u16{return 42;}',architecture:'nova16-v2'});
  assert.equal(result.ok,true,result.error);assert.equal(result.profile,2);
  result=await request({op:'vm',request:{op:'command',command:'continue'}});
  assert.equal(result.state.registers[0],42);assert.equal(result.state.halted,true);
  const saved=(await request({op:'vm',request:{op:'snapshot'}})).snapshot;
  const failure=await request({op:'build',source:'fn main()->u16{return missing;}'});
  assert.equal(failure.ok,false);
  assert.equal((await request({op:'vm',request:{op:'snapshot'}})).snapshot,saved);
  assert.equal(errors.length,0);
  console.log(JSON.stringify({schema_version:1,worker:'actual exported launcher/Worker source',threads:1,boot:'passed',queue_revision:'passed',typed_v2_build:'passed',execution:'R0=42',failure_retention:'passed'}));
} finally {if(thread)await thread.terminate();}

const deniedWindow={addEventListener(){}};
const denied=vm.createContext({window:deniedWindow,document:{getElementById(){return {textContent:assets};}},Blob:TestBlob,
  Worker:class{constructor(){throw Error('simulated Worker denial');}},
  URL:{createObjectURL(blob){urls.set('blob:denied',blob.code);return 'blob:denied';},revokeObjectURL(url){urls.delete(url);}}});
assert.throws(()=>new vm.Script(scripts[0]).runInContext(denied),/simulated Worker denial/);
await assert.rejects(deniedWindow.NovaOfflineRequest({op:'bootstrap'}),/initialization failed/);
assert.equal(urls.size,0,'Failed startup revokes the Blob URL');
console.log('Worker-denial fallback preserves offline mode and reports the failure without a server request');

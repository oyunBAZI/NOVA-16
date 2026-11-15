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
  setTimeout,clearTimeout,
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
  setTimeout,clearTimeout,
  Worker:class{constructor(){throw Error('simulated Worker denial');}},
  URL:{createObjectURL(blob){urls.set('blob:denied',blob.code);return 'blob:denied';},revokeObjectURL(url){urls.delete(url);}}});
assert.throws(()=>new vm.Script(scripts[0]).runInContext(denied),/simulated Worker denial/);
await assert.rejects(deniedWindow.NovaOfflineRequest({op:'bootstrap'}),/initialization failed/);
assert.equal(urls.size,0,'Failed startup revokes the Blob URL');
console.log('Worker-denial fallback preserves offline mode and reports the failure without a server request');

let failedWorker;
const failedWindow={addEventListener(){}};
const failedContext=vm.createContext({window:failedWindow,document:{getElementById(){return {textContent:assets};}},Blob:TestBlob,
  setTimeout,clearTimeout,
  Worker:class{constructor(){failedWorker=this;}postMessage(){}terminate(){}},
  URL:{createObjectURL(blob){urls.set('blob:failed',blob.code);return 'blob:failed';},revokeObjectURL(url){urls.delete(url);}}});
new vm.Script(scripts[0]).runInContext(failedContext);
const pending=failedWindow.NovaOfflineRequest({op:'bootstrap'});
failedWorker.onerror();
await assert.rejects(pending,/Worker failed/);
await assert.rejects(failedWindow.NovaOfflineRequest({op:'load',demo:'boot_splash'}),/Worker failed/);
assert.equal(urls.size,0);
console.log('Fatal Worker errors reject pending and future requests instead of leaving UI actions waiting');

function transport() {
  let worker, nextTimer=0, terminated=0;
  const timers=new Map(),events=new Map(),resources=new Set();
  const window={addEventListener(name,fn){events.set(name,fn);}};
  const context=vm.createContext({window,document:{getElementById(){return {textContent:assets};}},Blob:TestBlob,
    Worker:class{constructor(){worker=this;this.messages=[];}postMessage(value){this.messages.push(value);}terminate(){terminated++;}},
    setTimeout(fn,ms){assert.equal(ms,20000);timers.set(++nextTimer,fn);return nextTimer;},clearTimeout(id){timers.delete(id);},
    URL:{createObjectURL(){resources.add('blob:transport');return 'blob:transport';},revokeObjectURL(value){resources.delete(value);}},
    location:{reload(){events.set('reloaded',true);}}});
  new vm.Script(scripts[0]).runInContext(context);
  return {window,worker,timers,events,resources,terminated:()=>terminated};
}
{
  const t=transport();
  const pending=Array.from({length:16},()=>t.window.NovaOfflineRequest({op:'bootstrap'}));
  await assert.rejects(t.window.NovaOfflineRequest({op:'bootstrap'}),/queue is full/);
  assert.equal(t.timers.size,16);
  t.worker.onmessage({data:{id:999,response:{}}});
  assert.equal(t.timers.size,16,'Unknown/stale response IDs do not settle another request');
  const first=t.worker.messages[0];
  t.worker.onmessage({data:{id:first.id,response:{status:200,result:{ok:true}}}});
  assert.equal((await pending[0]).ok,true);
  assert.equal(t.timers.size,15);
  const rejections=pending.slice(1).map(job=>assert.rejects(job,/response budget/));
  [...t.timers.values()][0]();
  await Promise.all(rejections);
  assert.equal(t.timers.size,0);assert.equal(t.resources.size,0);assert.equal(t.terminated(),1);
  await assert.rejects(t.window.NovaOfflineRequest({op:'bootstrap'}),/response budget/);
  t.events.get('pagehide')();assert.equal(t.terminated(),1,'Disposal is idempotent');
}
for(const failure of ['messageerror','malformed','pagehide']) {
  const t=transport(),pending=t.window.NovaOfflineRequest({op:'bootstrap'});
  const rejected=assert.rejects(pending,/decoded|invalid response|page closed/);
  if(failure==='messageerror')t.worker.onmessageerror();
  if(failure==='malformed')t.worker.onmessage({data:{id:1,response:{status:200,result:null}}});
  if(failure==='pagehide')t.events.get('pagehide')();
  await rejected;
  assert.equal(t.timers.size,0);assert.equal(t.terminated(),1);assert.equal(t.resources.size,0);
  t.events.get('pageshow')({persisted:true});assert.equal(t.events.get('reloaded'),true);
}
{
  const t=transport();
  t.worker.postMessage=()=>{throw Error('simulated clone denial');};
  await assert.rejects(t.window.NovaOfflineRequest({op:'bootstrap'}),/clone denial/);
  assert.equal(t.timers.size,0);assert.equal(t.terminated(),0,'An unsent request does not kill the VM');
  t.worker.postMessage=value=>t.worker.messages.push(value);
  const pending=t.window.NovaOfflineRequest({op:'bootstrap'});
  t.worker.onmessage({data:{id:2,response:{status:200,result:{ok:true}}}});
  assert.equal((await pending).ok,true);assert.equal(t.timers.size,0);
  t.events.get('pagehide')();
}
console.log('Exported transport queue/timeouts, clone rejection, malformed messages and page lifecycle passed');

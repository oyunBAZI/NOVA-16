import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {fileURLToPath} from 'node:url';
import {createOfflineHost} from '../wasm/offline-host.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const filename=fs.existsSync(path.join(root,'zig-out/web/NOVA16-Offline-Workbench.html'))?'zig-out/web/NOVA16-Offline-Workbench.html':'web/NOVA16-Offline-Workbench.html';
const html=fs.readFileSync(path.join(root,filename),'utf8');
const asset=html.match(/<script id="nova-assets" type="application\/json">([\s\S]*?)<\/script>/);
assert.ok(asset,'Embedded assets');
const data=JSON.parse(asset[1]);
assert.equal(Object.keys(data.cartridges).length,11);
assert.ok(!/<script[^>]+src=/.test(html),'No script dependencies');
assert.ok(html.includes("connect-src 'none'"),'Offline network boundary');
let scripts=0;
for(const match of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)) {
  if(match[0].startsWith('<script id="nova-assets"')) continue;
  new vm.Script(match[1]);scripts++;
}
assert.equal(scripts,2,'Initializer and shared frontend');
const host=createOfflineHost(data);
let revision=0;
async function request(payload,status=200) {
  const response=await host({...payload,revision});
  assert.equal(response.status,status,response.result.error);
  if(typeof response.result.revision==='number') revision=response.result.revision;
  return response.result;
}
let result=await request({op:'bootstrap'});
assert.equal(result.state.machine_profile??1,1);
assert.equal(typeof result.editor_source,'string');
assert.equal(typeof result.source,'object');
await request({op:'load',demo:'nova_tracker'});
result=await request({op:'edit_demo',demo:'nova_tracker'});
assert.equal(result.editor_architecture,'nova16-v2');
result=await request({op:'build',source:result.editor_source,architecture:result.editor_architecture});
assert.equal(result.ok,true,result.error);
result=await request({op:'replay',frames:120,schedule:'30 16\n31 0\n100 64\n101 0'});
assert.equal(result.state.machine_profile,2);
assert.equal(result.audio.voices.every(v=>!v.enabled),true);
const saved=(await request({op:'vm',request:{op:'snapshot'}})).snapshot;
result=await request({op:'build',source:'fn main()->u16{return true;}'});
assert.equal(result.ok,false);assert.ok(result.diagnostics.includes('TypeMismatch'));
assert.equal((await request({op:'vm',request:{op:'snapshot'}})).snapshot,saved);
for(const payload of [{op:'replay',frames:3,schedule:'1 0\n0 1'},{op:'load',demo:'__proto__'},
  {op:'edit_demo',demo:'../secret'},{op:'build',source:'x',architecture:'secret'},
  {op:'replay',frames:0,schedule:''}]) {
  await request(payload,400);
  assert.equal((await request({op:'vm',request:{op:'snapshot'}})).snapshot,saved);
}
const stale=await host({op:'vm',request:{op:'command',command:'reset'},revision:revision-1});
assert.equal(stale.status,409);
assert.equal((await request({op:'vm',request:{op:'snapshot'}})).snapshot,saved);
result=await request({op:'build',source:'fn main()->u16{return 42;}',architecture:'nova16-v2'});
assert.equal(result.ok,true);
result=await request({op:'vm',request:{op:'command',command:'continue'}});
assert.equal(result.state.registers[0],42);assert.equal(result.state.halted,true);

// The same grammar corpus executes through both real hosts; all invalid
// schedules are rejected before reset or any guest mutation.
const schedules=JSON.parse(fs.readFileSync(path.join(root,'docs/quality/replay-cases.json'),'utf8'));
await request({op:'load',demo:'paint'});
for(const schedule of schedules.valid) {
  result=await request({op:'replay',frames:4,schedule});
  assert.equal(result.replay_frames,4);
}
const before=(await request({op:'vm',request:{op:'snapshot'}})).snapshot;
for(const schedule of [...schedules.invalid,'#'+'é'.repeat(4096)]) {
  await request({op:'replay',frames:4,schedule},400);
  assert.equal((await request({op:'vm',request:{op:'snapshot'}})).snapshot,before);
}
await request({op:'build',source:'fn main()->u16{return 42;}'});
result=await request({op:'replay',frames:120,schedule:''});
assert.equal(result.replay_frames,1);assert.equal(result.state.frame_count,1);
await request({op:'build',source:'fn main()->u16{return 42;}',architecture:'nova16-v2'});
result=await request({op:'replay',frames:120,schedule:''});
assert.equal(result.replay_frames,120);assert.equal(result.state.transition_slots,2400000);

for(const name of ['paint','nova_sound']) {
  const rom=Buffer.from(data.cartridges[name].rom,'base64');
  result=await request({op:'load_rom',data:rom.toString('hex')});
  assert.equal(result.ok,true);assert.equal(result.title,'Imported ROM');
  await request({op:'vm',request:{op:'frame'}});
  const saved=(await request({op:'vm',request:{op:'snapshot'}})).snapshot;
  const corrupt=Buffer.from(rom);corrupt[corrupt.length-1]^=1;
  for(const data of ['', '00',rom.subarray(0,-1).toString('hex'),corrupt.toString('hex')]) {
    const failure=await request({op:'load_rom',data});
    assert.equal(failure.ok,false);
    assert.equal((await request({op:'vm',request:{op:'snapshot'}})).snapshot,saved);
  }
  for(const data of [null,[],'x','00 00','00'.repeat(8225)])await request({op:'load_rom',data},400);
}
console.log(JSON.stringify({schema_version:1,offline_bytes:Buffer.byteLength(html),cartridges:11,inline_scripts:scripts,worker_host:'build/replay/restore/rejection/isolation passed'}));

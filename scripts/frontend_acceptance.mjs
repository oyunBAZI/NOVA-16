/** Execute the shipped app.js and real Wasm host with a small DOM test double.
 * This verifies event/state behavior, not browser layout, CSP or audio hardware.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {fileURLToPath} from 'node:url';
import {createOfflineHost} from '../wasm/offline-host.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const web=fs.existsSync(path.join(root,'zig-out/web/NOVA16-Offline-Workbench.html'))?'zig-out/web/NOVA16-Offline-Workbench.html':'web/NOVA16-Offline-Workbench.html';
const html=fs.readFileSync(path.join(root,'workbench/index.html'),'utf8');
const data=JSON.parse(fs.readFileSync(path.join(root,web),'utf8').match(/<script id="nova-assets" type="application\/json">([\s\S]*?)<\/script>/)[1]);
const source=fs.readFileSync(path.join(root,'workbench/app.js'),'utf8');

class Element {
  constructor(tag='div',attributes={}) {
    this.tagName=tag.toUpperCase();this.attributes={...attributes};this.dataset={};
    this.children=[];this.textContent='';this.innerHTML='';this.value=attributes.value??'';
    this.style={};this.scrollTop=0;this.scrollLeft=0;this.scrollHeight=0;
    this.clientWidth=600;this.clientHeight=300;this.width=128;this.height=96;
    this.files=[];this.disabled=Object.hasOwn(attributes,'disabled');this.hidden=Object.hasOwn(attributes,'hidden');
    this.checked=Object.hasOwn(attributes,'checked');this.listeners=new Map();
    this.classes=new Set();
    this.classList={add:name=>this.classes.add(name),remove:name=>this.classes.delete(name),
      toggle:(name,on)=>{if(on??!this.classes.has(name))this.classes.add(name);else this.classes.delete(name);},contains:name=>this.classes.has(name)};
    for(const [key,value]of Object.entries(attributes))if(key.startsWith('data-'))this.dataset[key.slice(5)]=value;
  }
  append(...nodes) {this.children.push(...nodes);if(this.tagName==='SELECT'&&this.children.length===1)this.value=nodes[0].value;}
  replaceChildren(...nodes) {this.children=[...nodes];}
  before(node) {this.beforeElement=node;}
  setAttribute(key,value) {this.attributes[key]=value;}
  getAttribute(key) {return this.attributes[key];}
  addEventListener(name,handler) {if(!this.listeners.has(name))this.listeners.set(name,[]);this.listeners.get(name).push(handler);}
  dispatchEvent(event) {event.target??=this;this['on'+event.type]?.(event);for(const handler of this.listeners.get(event.type)??[])handler(event);return true;}
  click() {if(!this.disabled)return this.onclick?.({target:this,preventDefault(){}});}
  setPointerCapture() {}
  showModal() {this.open=true;}
  close() {this.open=false;}
  getBoundingClientRect() {return {left:0,top:0,width:256,height:192};}
  getContext() {return {createImageData:(w,h)=>({data:new Uint8ClampedArray(w*h*4)}),putImageData(){},clearRect(){},beginPath(){},moveTo(){},lineTo(){},stroke(){}};}
}
function parseAttributes(text) {
  return Object.fromEntries([...text.matchAll(/([\w-]+)(?:="([^"]*)")?/g)].map(match=>[match[1],match[2]??'']));
}
function storage(values=new Map()) {return {getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};}
async function frontend({drafts=new Map(),denyStorage=false,native=false,delay}={}) {
  const elements=new Map(),buttons=[],requests=[],downloads=[],errors=[],events=new Map();
  for(const match of html.matchAll(/<([a-z]+)\b([^>]*)>/g)) {
    const attributes=parseAttributes(match[2]);const element=new Element(match[1],attributes);
    if(attributes.id)elements.set(attributes.id,element);
    if(attributes['data-bit'])buttons.push(element);
  }
  const $=id=>elements.get(id);
  $('build-architecture').value='nova16-v1';$('build-optimization').value='size';
  const document=new Element();document.hidden=false;document.activeElement=null;
  document.getElementById=id=>{assert.ok(elements.has(id),'Unknown DOM element '+id);return $(id);};
  document.createElement=tag=>{const element=new Element(tag);if(tag==='a')element.click=()=>downloads.push({name:element.download,url:element.href});return element;};
  document.querySelectorAll=selector=>selector==='[data-bit]'?buttons:[];
  const host=createOfflineHost(data);
  const request=async payload=> {
    requests.push(JSON.parse(JSON.stringify(payload)));
    if(delay)await delay(payload);
    const response=await host(payload);
    return {ok:response.status>=200&&response.status<300,json:async()=>response.result};
  };
  const window={addEventListener(name,fn){if(!events.has(name))events.set(name,[]);events.get(name).push(fn);}};
  if(!native)window.NovaOfflineRequest=request;
  for(const name of ['localStorage','sessionStorage']) {
    Object.defineProperty(window,name,{get(){if(denyStorage)throw Error('storage denied');return name==='localStorage'?storage(drafts):storage();}});
  }
  let audioCount=0;
  class AudioContext {
    constructor(){audioCount++;this.state='suspended';this.currentTime=0;}
    async resume(){this.state='running';}
    async close(){this.state='closed';}
    createBuffer(_,length,rate){return {copyToChannel(){},duration:length/rate};}
    createBufferSource(){return {connect(){},start(){},stop(){}};}
  }
  const context=vm.createContext({window,document,console,TextEncoder,TextDecoder,Uint8Array,Uint8ClampedArray,Float32Array,ArrayBuffer,DataView,
    setTimeout,clearTimeout,performance,AudioContext,
    Blob,URL:{createObjectURL:()=> 'blob:download',revokeObjectURL(){}},
    confirm:()=>true,location:{hash:'#test-token'},history:{replaceState(){}},
    fetch:async(url,options)=>{assert.equal(url,'/api');return request(JSON.parse(options.body));},
    ResizeObserver:class{observe(){}},Event:class{constructor(type){this.type=type;}}});
  new vm.Script(source,{filename:'workbench/app.js'}).runInContext(context);
  const evaluate=code=>vm.runInContext(code,context);
  const flush=async()=>{await Promise.resolve();await evaluate('serial');await Promise.resolve();};
  await flush();
  assert.equal(evaluate('editorReady'),true);
  return {$,document,buttons,requests,downloads,errors,events,evaluate,flush,drafts,
    state:()=>JSON.parse(evaluate('JSON.stringify(current)')),
    async key(code,down=true) {for(const fn of events.get(down?'keydown':'keyup')??[])fn({key:code,code,preventDefault(){}});await flush();},
    async emit(name,event={}) {for(const fn of events.get(name)??[])fn(event);await flush();},
    async edit(text) {$('source').value=text;$('source').oninput();await flush();},
    async command(text) {$('command').value=text;$('command-form').onsubmit({preventDefault(){}});await flush();},
    close(){evaluate('pause();clearTimeout(draftTimer);');},audioCount:()=>audioCount};
}

let checks=0;
async function check(name,fn) {await fn();checks++;console.log('PASS '+name);}

await check('actual frontend boot, optional storage denial and native token fallback',async()=> {
  for(const native of [false,true]) {
    const f=await frontend({denyStorage:true,native});
    try {
      assert.equal(f.state().profile,1);assert.equal(f.$('demos').children.length,11);
      assert.equal(f.$('source').value,data.editor_source);
      assert.match(f.$('draft-status').textContent,/unavailable/);
      assert.equal(f.audioCount(),0,'Audio requires a gesture');
      let prevented=false;await f.emit('beforeunload',{preventDefault(){prevented=true;}});
      assert.equal(prevented,true,'Warn when recovery is unavailable');
    } finally {f.close();}
  }
});

await check('successful build mappings, edits/undo, failed builds and ROM reload',async()=> {
  const f=await frontend();
  try {
    const text='fn main()->u16 {\n var x:u16=41;\n return x+1;\n}';
    await f.edit(text);await f.$('build').click();await f.flush();
    assert.equal(f.evaluate('sourceMatches'),true);
    assert.equal(f.$('download-rom').disabled,false);
    await f.$('step').click();await f.flush();
    assert.doesNotMatch(f.$('source-location').textContent,/compiled ROM/);
    await f.edit(text+'\n');
    assert.equal(f.evaluate('sourceMatches'),false);
    assert.match(f.$('source-location').textContent,/compiled ROM/);
    await f.edit(text);
    assert.equal(f.evaluate('sourceMatches'),true,'Undo back to built bytes restores mapping');
    f.$('build-architecture').value='nova16-v2';f.$('build-architecture').onchange();
    assert.equal(f.evaluate('sourceMatches'),false,'Target is part of build identity');
    f.$('build-architecture').value='nova16-v1';f.$('build-architecture').onchange();
    const saved=await f.evaluate("vm({op:'snapshot'})");
    await f.edit('fn main()->u16{return missing;}');await f.$('build').click();await f.flush();
    assert.equal(f.state().ok,false);assert.match(f.$('diagnostics').textContent,/UndefinedVariable/);
    assert.equal((await f.evaluate("vm({op:'snapshot'})")).snapshot,saved.snapshot);
    assert.equal(f.$('download-rom').disabled,false,'Last valid ROM remains exportable');
    f.$('demos').value='paint';await f.$('load').click();await f.flush();
    assert.equal(f.evaluate('sourceMatches'),false);assert.equal(f.$('download-rom').disabled,true);
    assert.equal(f.$('source').value,'fn main()->u16{return missing;}','Load preserves editor');
  } finally {f.close();}
});

await check('in-flight builds retain submitted source identity when editor changes',async()=> {
  let unblock;const gate=new Promise(resolve=>unblock=resolve);let submitted;
  const f=await frontend({delay:async payload=>{if(payload.op==='build'){submitted=payload.source;await gate;}}});
  try {
    await f.edit('fn main()->u16{return 7;}');const building=f.$('build').click();
    await new Promise(resolve=>setImmediate(resolve));
    assert.equal(submitted,'fn main()->u16{return 7;}');
    f.$('source').value='fn main()->u16{return 8;}';f.$('source').oninput();
    unblock();await building;await f.flush();
    assert.equal(f.evaluate('sourceMatches'),false);
    assert.equal(f.$('source-status').textContent,'UNBUILT CHANGES');
    await f.edit(submitted);assert.equal(f.evaluate('sourceMatches'),true);
  } finally {unblock();f.close();}
});

await check('keyboard/pointer ownership, dual Shift, lost capture and historic input',async()=> {
  const f=await frontend();
  try {
    f.document.activeElement=f.$('screen');
    await f.key('ShiftLeft');await f.key('ShiftRight');await f.key('ShiftLeft',false);
    assert.equal(f.state().input_held,128);
    await f.key('ShiftRight',false);assert.equal(f.state().input_held,0);
    await f.key('KeyZ');const a=f.buttons.find(b=>b.dataset.bit==='16');
    a.onpointerdown({pointerId:7,preventDefault(){}});await f.flush();
    await f.key('KeyZ',false);assert.equal(f.state().input_held,16);
    a.onlostpointercapture({pointerId:7});await f.flush();assert.equal(f.state().input_held,0);
    await f.command('input 32');assert.equal(f.buttons.find(b=>b.dataset.bit==='32').getAttribute('aria-pressed'),'true');
    await f.emit('blur');assert.equal(f.state().input_held,0,'Blur releases VM input even without a physical owner');
    await f.key('KeyX');await f.$('reset').click();await f.flush();assert.equal(f.state().input_held,0);
    await f.key('KeyX',false);assert.equal(f.state().input_held,0);
    await f.key('KeyZ');await f.key('KeyZ',false);await f.$('reverse').click();await f.flush();
    assert.equal(f.state().input_held,16,'Reverse restores guest device state');
    await f.emit('blur');assert.equal(f.state().input_held,0);
    assert.ok(f.buttons.every(b=>b.getAttribute('aria-pressed')==='false'));
  } finally {f.close();}
});

await check('draft recovery validates schema, source byte limits and target',async()=> {
  const drafts=new Map();let f=await frontend({drafts});
  const text='// Persian: سلام\nfn main()->u16{return 9;}';
  await f.edit(text);f.$('build-architecture').value='nova16-v2';f.$('build-architecture').onchange();
  f.evaluate('saveDraftNow()');f.close();
  f=await frontend({drafts});
  try {
    assert.equal(f.$('source').value,text);assert.equal(f.$('build-architecture').value,'nova16-v2');
    assert.equal(f.state().title,data.cartridges.boot_splash.title);
    assert.equal(f.evaluate('sourceMatches'),false);assert.match(f.$('source-status').textContent,/DRAFT RECOVERED/);
  } finally {f.close();}
  for(const value of ['{broken',JSON.stringify({version:2,source:'x'}),JSON.stringify({version:1,source:'é'.repeat(32769),architecture:'nova16-v1',optimization:'size'})]) {
    f=await frontend({drafts:new Map([['nova16-workbench-draft-v1',value]])});
    try {assert.equal(f.$('source').value,data.editor_source);}finally{f.close();}
  }
});

await check('source import is bounded UTF-8, repeatable, independent of live ROM',async()=> {
  const f=await frontend();
  try {
    const initial=f.state().state.rom_checksum;
    for(const value of [new TextEncoder().encode('fn main()->u16{return 88;}'),Uint8Array.from([0xff]),new Uint8Array(65537),Uint8Array.from([0])]) {
      const before=f.$('source').value;
      f.$('source-file').files=[{size:value.length,arrayBuffer:async()=>value.buffer}];
      await f.$('source-file').onchange();await f.flush();
      if(value[0]===102)assert.notEqual(f.$('source').value,before);
      else if(value[0]!==102)assert.equal(f.$('source').value,before);
      assert.equal(f.state().state.rom_checksum,initial);
      assert.equal(f.$('source-file').value,'');
    }
    assert.equal(f.$('source').value,'fn main()->u16{return 88;}');
  } finally {f.close();}
});

await check('transport pause status updates during an outstanding frame',async()=> {
  let unblock,started;const gate=new Promise(resolve=>unblock=resolve),frameStarted=new Promise(resolve=>started=resolve);
  const f=await frontend({delay:async payload=>{if(payload.op==='vm'&&payload.request.op==='frame'){started();await gate;}}});
  try {
    const run=f.$('run').click();await frameStarted;
    assert.equal(f.$('machine-status').textContent,'RUNNING');
    assert.equal(f.$('run').getAttribute('aria-pressed'),'true');
    f.$('run').click();assert.equal(f.$('machine-status').textContent,'READY');
    unblock();await run;await f.flush();
    assert.equal(f.$('run').getAttribute('aria-pressed'),'false');
    assert.equal(f.requests.filter(r=>r.request?.op==='frame').length,1,'Pause schedules no additional frame');
  } finally {unblock();f.close();}
});

console.log(JSON.stringify({schema_version:1,checks,frontend:'shipped app.js with real Wasm/compiler host',browser_rendering:false}));

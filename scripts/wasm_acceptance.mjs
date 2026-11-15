/** Actual WebAssembly execution, compared with native ROM/compiler/snapshot output. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createMachine} from '../wasm/nova16.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const bin=fs.existsSync(path.join(root,'zig-out/bin'))?'zig-out/bin':'bin';
const demos=fs.existsSync(path.join(root,'zig-out/demos'))?'zig-out/demos':'demos';
const wasm=fs.existsSync(path.join(root,'zig-out/wasm/nova16.wasm'))?'zig-out/wasm/nova16.wasm':'wasm/nova16.wasm';
const suffix=process.platform==='win32'?'.exe':'';
function native(name,args,input) {
  const p=spawnSync(path.join(root,bin,name+suffix),args,{input,encoding:'utf8',timeout:60000,maxBuffer:64*1024*1024});
  assert.equal(p.status,0,`${name}: ${p.stderr}`);
  return p.stdout;
}
const bytes=fs.readFileSync(path.join(root,wasm));
const module=await WebAssembly.compile(bytes);
assert.deepEqual(WebAssembly.Module.imports(module),[]);
const machine=await createMachine(module);
assert.equal(machine.version,native('nova16',['--version']).trim());
assert.equal(machine.request({}).error,'NoRomLoaded');
const names=fs.readdirSync(path.join(root,demos)).filter(p=>p.endsWith('.n16')).sort();
let comparisons=0;
for (const file of names) {
  const rom=path.join(root,demos,file);
  const loaded=machine.load(fs.readFileSync(rom));
  assert.equal(loaded.ok,true,file);
  const requests=[{}, {op:'frame'}, {op:'frame'}, {op:'frame'}, {op:'snapshot'},
    {op:'command',command:'step 32'}, {op:'command',command:'input 165'},
    {address:0xd800}, {address:0xd800}, {op:'replay_frame'}, {op:'snapshot'},
    {op:'command',command:'reverse'}, {op:'snapshot'},
    {op:'command',command:'savesnap forbidden'}, {version:2}, {op:'bad'},
    {address:65535,length:256}, {op:'observe',unexpected:true}];
  const lines=native('n16bridge',[rom],requests.map(r=>JSON.stringify(r)).join('\n')+'\n').trim().split('\n').map(JSON.parse);
  for (let i=0;i<requests.length;i++) {
    const actual=machine.request(requests[i]), expected=lines[i];
    for (const key of ['ok','error','state','vram','palette','input_held','input_pressed','audio','snapshot']) {
      assert.deepEqual(actual[key],expected[key],`${file} request ${i}: ${key}`);
      comparisons++;
    }
  }
  const base=file.slice(0,-4);
  const symbolFile=['.map.json','.sym2','.sym'].map(ext=>path.join(root,demos,base+ext)).find(p=>fs.existsSync(p));
  if(symbolFile) {
    assert.equal(machine.setSymbols(fs.readFileSync(symbolFile,'utf8')).ok,true);
    const request={op:'command',command:'symbols'};
    const expected=JSON.parse(native('n16bridge',[rom,'--symbols',symbolFile],JSON.stringify(request)+'\n'));
    // A following request overwrites the shared input buffer. Legacy names must
    // remain owned by the loaded map rather than borrow that scratch buffer.
    assert.equal(machine.request(request).output,expected.output,`${file}: symbol lifetime`);
    machine.request({op:'observe',address:0xd800});
    assert.equal(machine.request(request).output,expected.output,`${file}: symbol lifetime after reuse`);
  }
  const before=machine.request({op:'snapshot'}).snapshot;
  assert.equal(machine.load(new Uint8Array([0,1,2])).ok,false);
  assert.equal(machine.request({op:'snapshot'}).snapshot,before);
  assert.equal(machine.rawRequest('not json').error,'BadRequest');
  console.log(`${file}: native/Wasm state, pixels, PCM, snapshots, rewind and rejection parity passed`);
}
machine.load(fs.readFileSync(path.join(root,demos,'boot_splash.n16')));
const checksum=machine.request({}).state.rom_checksum;
const largeMap={schema_version:2,rom_checksum:checksum,symbols:Array.from({length:3000},(_,i)=>({name:'symbol_'+String(i).padStart(5,'0')+'_'+'x'.repeat(48),value:0xe000})),locations:[]};
assert.equal(machine.setSymbols(JSON.stringify(largeMap)).ok,true);
const unchanged=machine.request({op:'snapshot'}).snapshot;
assert.equal(machine.request({op:'command',command:'symbols'}).error,'OutputLimit');
assert.equal(machine.request({op:'snapshot'}).snapshot,unchanged);
const entry=machine.request({}).state.pc;
const giantLocation={schema_version:2,rom_checksum:checksum,symbols:[],locations:[{address:entry,length:2,file:'x'.repeat(600000),line:1,column:1}]};
assert.equal(machine.setSymbols(JSON.stringify(giantLocation)).error,'OutputLimit');
assert.equal(machine.request({op:'command',command:'step'}).state.executed_instructions,1);
assert.equal(machine.request({op:'snapshot'}).ok,true);
console.log('Oversized valid inspections return bounded errors and retain the live machine');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'nova16-wasm-'));
try {
  const main=path.join(temporary,'main.n16c'), rom=path.join(temporary,'program.n16');
  for (const app of ['crates','pixel_studio','nova_tracker','starfall']) {
    const source=fs.readFileSync(path.join(root,'examples/projects',app,'main.n16c'),'utf8');
    const profile=['nova_tracker','starfall'].includes(app)?2:1;
    fs.writeFileSync(main,source);
    native('n16c',[main,'--architecture',`nova16-v${profile}`,'--out',rom]);
    const result=machine.compile(source,{profile});
    assert.equal(result.ok,true,`${app}: ${result.error}`);
    assert.equal(result.rom,fs.readFileSync(rom).toString('hex'),`${app}: compiler bytes`);
    const before=machine.request({op:'snapshot'}).snapshot;
    assert.equal(machine.compile('fn main()->u16{return true;}').error,'TypeMismatch');
    assert.equal(machine.request({op:'snapshot'}).snapshot,before);
    console.log(`${app}: native/Wasm compiler ROM bytes and failed-build retention passed`);
  }
  for (const optimize of [false,true]) {
    const result=machine.compile('fn main()->u16{var x:u16=65535;return x/16+x%8;}',{profile:2,optimize});
    assert.equal(result.ok,true);
    assert.equal(machine.request({op:'command',command:'continue'}).state.registers[0],4102);
  }
  assert.throws(()=>machine.compile('fn main()->u16{return 0;}',{profile:4294967297}),RangeError);
  const small='fn main()->u16{return 42;}';
  // Repeated replacement/restore releases compiler contexts, maps and request arenas.
  let warmPages=0;
  for(let i=0;i<100;i++) {
    assert.equal(machine.compile(small,{profile:1+(i%2)}).ok,true);
    const first=machine.request({op:'snapshot'}).snapshot;
    machine.request({op:'frame'});
    assert.equal(machine.request({op:'restore',data:first}).ok,true);
    assert.equal(machine.request({op:'snapshot'}).snapshot,first);
    if(i===20) warmPages=machine.exports.memory.buffer.byteLength/65536;
  }
  const pages=machine.exports.memory.buffer.byteLength/65536;
  assert.ok(pages<=1024,'64 MiB memory ceiling');
  assert.ok(pages<=warmPages+16,`unbounded memory growth: ${warmPages} -> ${pages}`);
  const independent=await createMachine(module);
  assert.equal(independent.request({}).error,'NoRomLoaded');
  assert.equal(machine.request({}).state.rom_checksum!==undefined,true);
  independent.dispose();machine.dispose();
  assert.equal(machine.request({}).error,'NoRomLoaded');
  assert.equal(machine.load(fs.readFileSync(path.join(root,demos,names[0]))).ok,true);
  machine.dispose();
  console.log(JSON.stringify({schema_version:1,roms:names.length,comparisons,compiler_replacement_cycles:100,wasm_bytes:bytes.length,memory_pages:pages}));
} finally { fs.rmSync(temporary,{recursive:true,force:true}); }

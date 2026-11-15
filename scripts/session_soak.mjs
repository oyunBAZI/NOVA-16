/** Stateful native/Wasm transport and lifetime soak. Same core, different hosts:
 * this is host parity/retention evidence, not an independent ISA oracle.
 * Each seed generates reproducible operations; a wall-clock budget determines
 * how many complete cycles execute. Use --cycles for an exact deterministic run.
 */
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import readline from 'node:readline';
import {fileURLToPath} from 'node:url';
import {createMachine} from '../wasm/nova16.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const installed=!fs.existsSync(path.join(root,'zig-out/bin'));
const bin=path.join(root,installed?'bin':'zig-out/bin');
const demos=path.join(root,installed?'demos':'zig-out/demos');
const wasmPath=path.join(root,installed?'wasm/nova16.wasm':'zig-out/wasm/nova16.wasm');
const suffix=process.platform==='win32'?'.exe':'';
const options={seconds:30,cycles:1000000000,seed:0x4e313651,out:path.join(root,'zig-out/session-soak.json')};
for(let i=2;i<process.argv.length;i+=2) {
  const name=process.argv[i].replace(/^--/,'');
  if(!Object.hasOwn(options,name)||process.argv[i+1]===undefined)throw Error('Usage: --seconds N --cycles N --seed N --out PATH');
  options[name]=name==='out'?process.argv[i+1]:Number(process.argv[i+1]);
}
assert.ok(Number.isFinite(options.seconds)&&options.seconds>=0&&options.seconds<=7200);
assert.ok(Number.isSafeInteger(options.cycles)&&options.cycles>0&&options.cycles<=1000000000);
assert.ok(Number.isSafeInteger(options.seed)&&options.seed>0&&options.seed<=0xffffffff);
assert.ok(options.seconds>0||options.cycles<1000000000,'Use a finite time or cycle budget');
let randomState=options.seed;
function random(n) {randomState^=randomState<<13;randomState^=randomState>>>17;randomState^=randomState<<5;return (randomState>>>0)%n;}
const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
const report={schema_version:1,seed:options.seed,started_utc:new Date().toISOString(),seconds_budget:options.seconds,
  cycle_budget:options.cycles,host_parity:true,independent_isa_oracle:false,cycles:0,requests:0,compiled:0,
  roms:{},operations:{},wasm_sha256:hash(fs.readFileSync(wasmPath)),passed:false,last_requests:[]};
const directory=fs.mkdtempSync(path.join(os.tmpdir(),'nova16-soak-'));
// Freeze executables for the run. Parallel Debug/ReleaseSafe validation may
// reinstall zig-out/bin; a soak must retain an identifiable binary pair.
const nativeBin=path.join(directory,'bin');fs.mkdirSync(nativeBin);
report.native_sha256={};
for(const name of ['n16bridge','n16c']) {
  const target=path.join(nativeBin,name+suffix);
  fs.copyFileSync(path.join(bin,name+suffix),target);fs.chmodSync(target,0o755);
  report.native_sha256[name]=hash(fs.readFileSync(target));
}
const started=performance.now();let lastSave=0,bridge;
function save() {
  report.seconds=Number(((performance.now()-started)/1000).toFixed(3));
  fs.mkdirSync(path.dirname(path.resolve(options.out)),{recursive:true});
  const temporary=options.out+'.tmp';fs.writeFileSync(temporary,JSON.stringify(report,null,2)+'\n');fs.renameSync(temporary,options.out);
}
class Bridge {
  constructor(rom) {
    this.child=spawn(path.join(nativeBin,'n16bridge'+suffix),[rom],{stdio:['pipe','pipe','pipe']});
    this.errorText='';this.pending=null;this.closed=false;
    this.lines=readline.createInterface({input:this.child.stdout,crlfDelay:Infinity});
    this.child.stderr.on('data',chunk=>this.errorText=(this.errorText+chunk).slice(-4000));
    this.lines.on('line',line=> {
      if(!this.pending)return this.fail(Error('Unsolicited native response'));
      const job=this.pending;this.pending=null;clearTimeout(job.timer);
      try {assert.ok(line.length<=512000);job.resolve(JSON.parse(line));}catch(error){job.reject(error);}
    });
    this.child.on('error',error=>this.fail(error));
    this.child.on('exit',(code,signal)=>this.fail(Error(`Native bridge exited: ${code}/${signal} ${this.errorText}`)));
    this.child.stdin.on('error',error=>this.fail(error));
  }
  fail(error) {this.closed=true;if(this.pending){clearTimeout(this.pending.timer);this.pending.reject(error);this.pending=null;}}
  request(text) {
    assert.equal(this.pending,null,'One native request at a time');
    if(this.closed)throw Error('Native bridge closed: '+this.errorText);
    return new Promise((resolve,reject)=> {
      const timer=setTimeout(()=>this.fail(Error('Native response exceeded 10 seconds')),10000);
      this.pending={resolve,reject,timer};
      this.child.stdin.write(text+'\n');
    });
  }
  async close() {
    if(this.child.exitCode!==null)return;
    const exited=new Promise(resolve=>this.child.once('exit',resolve));
    this.child.stdin.end();
    const timer=setTimeout(()=>this.child.kill(),2000);
    try {await exited;}finally{clearTimeout(timer);this.lines.close();}
  }
}
const machine=await createMachine(fs.readFileSync(wasmPath));
const names=fs.readdirSync(demos).filter(name=>name.endsWith('.n16')).sort();
const fields=['ok','error','state','vram','palette','input_held','input_pressed','audio','snapshot',
  'source','disassembly','breakpoints','memory_address','memory','stopped','history_count'];
async function request(payload) {
  const text=typeof payload==='string'?payload:JSON.stringify(payload);
  const label=typeof payload==='string'?'raw':payload.op??'observe';
  report.operations[label]=(report.operations[label]??0)+1;
  report.last_requests.push(typeof payload==='string'?{raw_bytes:text.length}: {...payload,data:payload.data?{bytes:payload.data.length/2,sha256:hash(payload.data)}:undefined});
  if(report.last_requests.length>16)report.last_requests.shift();
  const native=await bridge.request(text),portable=machine.rawRequest(text);
  report.requests++;
  for(const key of fields)assert.deepEqual(portable[key],native[key],`${report.current_rom}: request ${report.requests}, ${label}, ${key}`);
  // History byte counts depend on native/wasm pointer width. Every other debug
  // command's output must match, in addition to the actual guest state above.
  if(!payload.command?.startsWith('history'))assert.equal(portable.output,native.output);
  report.wasm_memory_bytes=machine.exports.memory.buffer.byteLength;
  report.maximum_wasm_memory_bytes=Math.max(report.maximum_wasm_memory_bytes??0,report.wasm_memory_bytes);
  assert.ok(report.wasm_memory_bytes<=64*1024*1024);
  return portable;
}
try {
  while(report.cycles<options.cycles && (!options.seconds || performance.now()-started<options.seconds*1000)) {
    let rom=path.join(demos,names[random(names.length)]);
    if(report.cycles%7===6) {
      const profile=1+random(2),optimization=random(2)?'size':'none';
      const source=`var calls:u16=0; fn tap(x:u16)->u16{calls=calls+1;return x;} fn main()->u16{var a:u16=${random(65536)};var b:u16=${random(65536)};return tap(a)+tap(b)+(calls<<${random(16)});}`;
      fs.writeFileSync(path.join(directory,'main.n16c'),source);rom=path.join(directory,'program.n16');
      const build=spawnSync(path.join(nativeBin,'n16c'+suffix),[path.join(directory,'main.n16c'),'--out',rom,
        '--architecture','nova16-v'+profile,'--optimize',optimization],{encoding:'utf8',timeout:15000});
      assert.equal(build.status,0,build.stderr);
      const compiled=machine.compile(source,{profile,optimize:optimization==='size'});
      assert.equal(compiled.ok,true,compiled.error);assert.equal(compiled.rom,fs.readFileSync(rom).toString('hex'));
      report.compiled++;
    }
    report.current_rom=path.basename(rom);report.roms[report.current_rom]=(report.roms[report.current_rom]??0)+1;
    assert.equal(machine.load(fs.readFileSync(rom)).ok,true);
    bridge=new Bridge(rom);
    await request({op:'command',command:'history delta 64'});
    const saved=[];
    for(let index=0;index<48;index++) {
      let payload;
      switch(random(17)) {
        case 0:case 1:payload={op:'frame'};break;
        case 2:payload={op:'replay_frame'};break;
        case 3:payload={op:'command',command:'step '+random(80)};break;
        case 4:payload={op:'command',command:'continue '+random(200)};break;
        case 5:payload={op:'command',command:'input '+random(256)};break;
        case 6:payload={op:'command',command:'reverse'};break;
        case 7:payload={op:'observe',address:random(65536),length:random(257)};break;
        case 8:payload={op:'command',command:['break 0xe000','delete 0xe000','watch 0xc000','unwatch 0xc000'][random(4)]};break;
        case 9:payload={op:'command',command:['regs','devices','trace 16','source','next 80','vars'][random(6)]};break;
        case 10:payload={op:'command',command:'reset'};break;
        case 11: {
          const state=await request({op:'snapshot'});saved.push(state.snapshot);if(saved.length>4)saved.shift();continue;
        }
        case 12:payload=saved.length?{op:'restore',data:saved[random(saved.length)]}:{op:'restore',data:'not hex'};break;
        case 13:payload=saved.length?{op:'restore',data:'00'+saved[random(saved.length)].slice(2)}:{version:2};break;
        case 14:payload=['not json',JSON.stringify({op:'observe',unknown:true}),'x'.repeat(150000)][random(3)];break;
        case 15:payload={op:'command',command:['step 20001','loadsnap forbidden','input 256','history delta 64'][random(4)]};break;
        default:payload={op:'observe',address:0xd800,length:256};break;
      }
      await request(payload);
    }
    await bridge.close();bridge=null;
    report.cycles++;
    if(performance.now()-lastSave>10000){lastSave=performance.now();save();}
  }
  report.passed=true;report.completed_utc=new Date().toISOString();save();
  console.log(JSON.stringify({...report,last_requests:undefined}));
}catch(error){report.failure=String(error.stack??error);save();throw error;}
finally {if(bridge)await bridge.close();machine.dispose();fs.rmSync(directory,{recursive:true,force:true});}

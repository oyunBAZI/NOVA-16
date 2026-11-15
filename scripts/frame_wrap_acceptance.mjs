/** Long-lived native/Wasm frame-counter, rewind and memory acceptance.
 * Host parity shares the core; expected counters and snapshot identities are
 * checked separately. No independent ISA-oracle or whole-browser memory claim.
 */
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createMachine} from '../wasm/nova16.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const installed=!fs.existsSync(path.join(root,'zig-out/bin'));
const options={frames:65552,out:path.join(root,'zig-out/frame-wrap.json')};
for(let i=2;i<process.argv.length;i+=2) {
  const key=process.argv[i].replace(/^--/,'');
  if(!Object.hasOwn(options,key)||process.argv[i+1]===undefined)throw Error('Usage: --frames N --out PATH');
  options[key]=key==='out'?process.argv[i+1]:Number(process.argv[i+1]);
}
assert.ok(Number.isSafeInteger(options.frames)&&options.frames>=64&&options.frames<=100000);
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'nova16-frame-wrap-'));
const suffix=process.platform==='win32'?'.exe':'';
const executable=path.join(temporary,'n16bridge'+suffix);
fs.copyFileSync(path.join(root,installed?'bin':'zig-out/bin','n16bridge'+suffix),executable);fs.chmodSync(executable,0o755);
const wasm=fs.readFileSync(path.join(root,installed?'wasm/nova16.wasm':'zig-out/wasm/nova16.wasm'));
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const report={schema_version:1,passed:false,started_utc:new Date().toISOString(),frames_per_profile:options.frames,
  native_sha256:hash(fs.readFileSync(executable)),wasm_sha256:hash(wasm),profiles:[],host_parity:true,independent_isa_oracle:false};
const started=performance.now();let peer;
function save() {
  report.seconds=Number(((performance.now()-started)/1000).toFixed(3));
  fs.mkdirSync(path.dirname(path.resolve(options.out)),{recursive:true});
  fs.writeFileSync(options.out+'.tmp',JSON.stringify(report,null,2)+'\n');fs.renameSync(options.out+'.tmp',options.out);
}
class Native {
  constructor(rom) {
    this.child=spawn(executable,[rom],{stdio:['pipe','pipe','pipe']});this.pending=null;this.fatal=null;this.closing=false;
    this.lines=readline.createInterface({input:this.child.stdout,crlfDelay:Infinity});
    this.child.stderr.resume();
    this.lines.on('line',line=> {
      const job=this.pending;
      if(!job)return this.fail(Error('Unexpected native response'));
      this.pending=null;clearTimeout(job.timer);
      try{assert.ok(line.length<=512000);job.resolve(JSON.parse(line));}catch(error){job.reject(error);}
    });
    this.child.on('error',error=>this.fail(error));this.child.stdin.on('error',error=>this.fail(error));
    this.child.on('exit',code=>{if(!this.closing)this.fail(Error('Native exited '+code));});
  }
  fail(error) {this.fatal=error;if(this.pending){clearTimeout(this.pending.timer);this.pending.reject(error);this.pending=null;}}
  request(payload) {
    if(this.fatal)return Promise.reject(this.fatal);
    assert.equal(this.pending,null);
    return new Promise((resolve,reject)=> {
      const timer=setTimeout(()=>{this.fail(Error('Native request exceeded 10 seconds'));this.child.kill();},10000);
      this.pending={resolve,reject,timer};this.child.stdin.write(JSON.stringify(payload)+'\n');
    });
  }
  rss() {
    try {return Number(fs.readFileSync(`/proc/${this.child.pid}/status`,'utf8').match(/^VmHWM:\s+(\d+)/m)[1])*1024;}catch{return null;}
  }
  async close() {
    this.closing=true;if(this.child.exitCode!==null)return;
    const exit=new Promise(resolve=>this.child.once('exit',resolve));this.child.stdin.end();
    const timer=setTimeout(()=>this.child.kill(),2000);try{await exit;}finally{clearTimeout(timer);this.lines.close();}
  }
}
const machine=await createMachine(wasm);
const keys=['ok','error','state','vram','palette','input_held','input_pressed','audio','snapshot','history_count','history_capacity','stopped'];
async function request(payload) {
  const actual=await peer.request(payload),portable=machine.request(payload);
  for(const key of keys)assert.deepEqual(portable[key],actual[key],`${report.current_profile}: ${payload.op} ${key}`);
  assert.equal(actual.ok,true,actual.error);return actual;
}
try {
  for(const [profile,name]of [[1,'bouncing_pixel'],[2,'nova_sound']]) {
    report.current_profile=profile;
    const rom=path.join(root,installed?'demos':'zig-out/demos',name+'.n16');
    assert.equal(machine.load(fs.readFileSync(rom)).ok,true);peer=new Native(rom);
    await request({op:'command',command:'history delta 64'});
    const result={profile,rom:name,rom_sha256:hash(fs.readFileSync(rom)),frames_completed:0};report.profiles.push(result);
    let beforeReverse,final,warmPages,warmRss;
    const warmFrame=Math.min(256,Math.floor(options.frames/2));
    for(let frame=1;frame<=options.frames;frame++) {
      final=await request({op:'frame'});result.frames_completed=frame;
      assert.equal(final.state.frame_count,frame%65536,'Independent expected frame-counter wrap');
      if(profile===1)assert.equal(final.state.executed_instructions,frame*20000);
      else {
        assert.equal(final.state.transition_slots,frame*20000);
        assert.equal(final.state.audio_samples,frame*800);
      }
      assert.equal(final.state.trapped,false);
      if(frame===warmFrame){warmPages=machine.exports.memory.buffer.byteLength/65536;warmRss=peer.rss();}
      if(frame===options.frames-32)beforeReverse=(await request({op:'snapshot'})).snapshot;
      if(frame%256===0)save();
    }
    const finalSnapshot=(await request({op:'snapshot'})).snapshot;
    for(let index=0;index<32;index++)await request({op:'command',command:'reverse'});
    assert.equal((await request({op:'snapshot'})).snapshot,beforeReverse,'Rewind restores the exact pre-wrap state');
    for(let index=0;index<32;index++)await request({op:'frame'});
    assert.equal((await request({op:'snapshot'})).snapshot,finalSnapshot,'Re-execution crosses wrap identically');
    const pages=machine.exports.memory.buffer.byteLength/65536,rss=peer.rss();
    assert.ok(pages<=1024&&pages<=warmPages+16,'Wasm linear memory must remain bounded after warmup');
    if(rss!==null&&warmRss!==null)assert.ok(rss<=warmRss+8*1024*1024,'Long-lived native process must not accumulate request arenas');
    Object.assign(result,{counter_wraps:Math.floor(options.frames/65536),final_frame_counter:final.state.frame_count,
      final_instructions:final.state.executed_instructions,final_slots:final.state.transition_slots??null,
      rewind_frames:32,rewind_reexecution:'exact canonical snapshots',snapshot_sha256:hash(Buffer.from(finalSnapshot,'hex')),
      wasm_warm_pages:warmPages,wasm_final_pages:pages,native_warm_peak_rss:warmRss,native_final_peak_rss:rss});
    await peer.close();peer=null;save();
  }
  report.passed=true;report.completed_utc=new Date().toISOString();save();console.log(JSON.stringify(report));
}catch(error){report.failure=String(error.stack??error);save();throw error;}
finally{if(peer)await peer.close();machine.dispose();fs.rmSync(temporary,{recursive:true,force:true});}

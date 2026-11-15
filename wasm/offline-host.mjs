/** Local Worker model implementing the Workbench host contract using the real VM. */
import {createMachine} from './nova16.mjs';
export function decode64(text) {
  return Uint8Array.from(atob(text), c=>c.charCodeAt(0));
}
export function createOfflineHost(data) {
  let revision=0,title='',source=data.editor_source,architecture='nova16-v1',optimization='size';
  const ready=createMachine(decode64(data.wasm)).then(machine=> {
    const card=data.cartridges.boot_splash;
    const initial=machine.load(decode64(card.rom));
    if(!initial.ok) throw Error(initial.error);
    if(card.symbols) {
      const mapped=machine.setSymbols(card.symbols);
      if(!mapped.ok) throw Error(mapped.error);
    }
    title=card.title;
    return machine;
  });
  const plain=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
  const bytes=text=>new TextEncoder().encode(text).length;
  function schedule(text,frames) {
    if(typeof text!=='string'||text.length>8192||!Number.isInteger(frames)||frames<1||frames>120) throw Error('Replay needs 1–120 frames and a bounded schedule');
    const events=new Map();let previous=-1;
    for(const raw of text.split('\n')) {
      const line=raw.trim();if(!line||line.startsWith('#')) continue;
      const words=line.split(/\s+/);
      if(words.length!==2||words.some(word=>! /^(?:0x[0-9a-f]+|[0-9]+)$/i.test(word))) throw Error('Schedule lines are: frame mask');
      const [frame,bits]=words.map(Number);
      if(!(previous<frame&&frame<frames&&bits>=0&&bits<=255)) throw Error('Schedule must increase with frames in range and masks 0–255');
      events.set(frame,bits);previous=frame;
    }
    return events;
  }
  return async request=> {
    try {
      const machine=await ready;
      if(!plain(request)) throw Error('Request must be an object');
      if(bytes(JSON.stringify(request))>200000) throw Error('Request too large');
      if(request.op!=='bootstrap'&&(!Number.isInteger(request.revision)||request.revision!==revision)) return {status:409,result:{error:'Session changed; refresh before continuing',revision}};
      let result;
      switch(request.op) {
        case 'bootstrap':
          result=machine.request({});
          Object.assign(result,{editor_source:source,editor_architecture:architecture,editor_optimization:optimization,
            demos:Object.fromEntries(Object.entries(data.cartridges).map(([id,card])=>[id,card.title])),
            typed_demos:Object.fromEntries(Object.entries(data.cartridges).filter(([,card])=>card.source).map(([id,card])=>[id,card.architecture]))});
          break;
        case 'load': {
          const card=data.cartridges[request.demo];
          if(!Object.hasOwn(data.cartridges,request.demo)||!card) throw Error('Unknown demo');
          result=machine.load(decode64(card.rom));
          if(result.ok&&card.symbols) result=machine.setSymbols(card.symbols);
          if(result.ok) title=card.title;
          revision++;break;
        }
        case 'edit_demo': {
          const card=data.cartridges[request.demo];
          if(!Object.hasOwn(data.cartridges,request.demo)||!card?.source) throw Error('No typed source for this demo');
          source=card.source;architecture=card.architecture;
          result={...machine.request({}),editor_source:source,editor_architecture:architecture,editor_optimization:optimization};
          revision++;break;
        }
        case 'build': {
          const arch=request.architecture??'nova16-v1',opt=request.optimization??'size';
          if(!['nova16-v1','nova16-v2'].includes(arch)||!['size','none'].includes(opt)) throw Error('Invalid architecture or optimization');
          if(typeof request.source!=='string'||bytes(request.source)>65536) throw Error('Source must be text, at most 64 KiB');
          source=request.source;architecture=arch;optimization=opt;
          result=machine.compile(source,{profile:arch==='nova16-v1'?1:2,optimize:opt==='size'});
          if(result.ok) title='main.n16c';
          else result={...machine.request({}),ok:false,error:'Build failed; previous machine retained',diagnostics:JSON.stringify(result)};
          revision++;break;
        }
        case 'vm':
          if(!plain(request.request)) throw Error('Missing VM request');
          result=machine.request(request.request);revision++;break;
        case 'replay': {
          const events=schedule(request.schedule,request.frames);
          result=machine.request({op:'command',command:'reset'});
          for(let frame=0;frame<request.frames;frame++) {
            if(events.has(frame)) machine.request({op:'command',command:`input ${events.get(frame)}`});
            result=machine.request({op:'replay_frame'});
            if(!result.ok) break;
          }
          result.output=`Replayed ${request.frames} frames from reset.\n`+(result.output??'');
          revision++;break;
        }
        default:throw Error('Unknown operation');
      }
      return {status:200,result:{...result,revision,title}};
    }catch(error){return {status:400,result:{error:error.message,revision}};}
  };
}

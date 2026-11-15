'use strict';
const $ = id => document.getElementById(id);
const hex = (n, width = 4) => Number(n).toString(16).padStart(width, '0').toUpperCase();
const offline=Boolean(window.NovaOfflineRequest);
const token=offline?'':location.hash.slice(1)||sessionStorage.getItem('nova-token')||'';
if(!offline) {
  if(token) sessionStorage.setItem('nova-token',token);
  history.replaceState(null,'','/');
}
let revision = 0, current, previous, address = 0, running = false, serial = Promise.resolve();
let sourceMatches = false, romBytes = null, held = 0, sound = null, audioTime = 0;
let runGeneration = 0;
let highlightedSource = null, highlightedLine = -1;
let typedDemos = {};
const audioNodes = new Set();
const log = text => {
  $('console').textContent = ($('console').textContent + '\n' + text).slice(-18000);
  $('console').scrollTop = $('console').scrollHeight;
};
function stopSound() {
  for (const node of audioNodes) {
    try {
      node.stop();
    } catch (_) {
    }
  }
  audioNodes.clear();
  audioTime = 0;
}
function pause() {
  running = false;
  runGeneration++;
  $('run').textContent = '▶ Run';
  stopSound();
}
function api(payload) {
  const operation = async () => {
    const request={...payload,revision};
    const response = offline ? await window.NovaOfflineRequest(request) : await fetch('/api', {
      method: 'POST', headers: {
        'Content-Type': 'application/json', 'X-Nova-Token': token
      }, body: JSON.stringify({
        ...payload, revision
      })
    });
    const result = await response.json();
    if (typeof result.revision === 'number') revision = result.revision;
    if (!response.ok) throw Error(result.error || 'Local connection failed');
    if (result.state) render(result);
    if (result.output) log(result.output.trimEnd());
    if (result.error) {
      log(result.error);
      pause();
    }
    return result;
  };
  const job = serial.then(operation);
  serial = job.catch(error => {
    log(error.message);
    $('connection').textContent = error.message;
    pause();
  });
  return job;
}
function vm(request) {
  return api({
    op:'vm', request: {
      ...request, address, length:256
    }
  });
}
async function action(command) {
  pause();
  return vm({
    op:'command', command
  });
}
function download(name, bytes, type) {
  const url = URL.createObjectURL(new Blob([bytes], {
    type
  }));
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
const unhex = text => Uint8Array.from(text.match(/../g) || [], byte => parseInt(byte, 16));
function render(result) {
  previous = current;
  current = result;
  const s = result.state;
  $('connection').textContent = offline?'CONNECTED / WASM':'CONNECTED / NATIVE';
  const status = s.trapped ? 'TRAP' : s.halted ? 'HALT' : s.paused ? 'BRK' : running ? 'RUNNING' : 'READY';
  $('machine-status').textContent = status;
  $('status-dot').style.background = s.trapped ? '#f2ad98' : running ? '#a1edbc' : '#edc887';
  $('machine-title').textContent = result.title;
  $('profile').textContent = `PROFILE ${result.profile} · ROM CRC ${hex(s.rom_checksum, 8)}`;
  $('timing').textContent = `FRAME ${hex(s.frame_count)} · ${s.executed_instructions.toLocaleString()} INSTRUCTIONS`;
  $('flags').textContent = ['Z','N','C','V'].map((flag,i) => `${flag} ${(s.flags >> i) & 1}`).join(' · ');
  $('registers').replaceChildren();
  const values = [...s.registers, s.pc, s.sp];
  values.forEach((value, i) => {
    const el = document.createElement('div');
    el.className = 'register';
    const old = previous ? [...previous.state.registers, previous.state.pc, previous.state.sp][i] : value;
    if (old !== value) el.classList.add('changed');
    const label = document.createElement('small');
    label.textContent = i < 8 ? `R${i}` : i === 8 ? 'PC' : 'SP';
    const number = document.createElement('b');
    number.textContent = hex(value);
    el.append(label, number);
    $('registers').append(el);
  });
  $('disassembly').textContent = result.disassembly;
  $('history-count').textContent = `${result.history_count} / ${result.history_capacity} rewind entries`;
  $('reverse').disabled = result.history_count === 0;
  $('source-location').textContent = result.source ? `${result.source.file}:${result.source.line}:${result.source.column}${sourceMatches ? '' : ' · compiled ROM'}` : 'Source map not loaded';
  $('breakpoints').replaceChildren();
  for (const point of result.breakpoints) {
    const button = document.createElement('button');
    button.textContent = `● ${hex(point)} ×`;
    button.title = 'Remove breakpoint';
    button.onclick = () => action(`delete 0x${hex(point)}`).catch(() => {
    });
    $('breakpoints').append(button);
  }
  $('input-state').textContent = `INPUT ${hex(result.input_held,2)} · EDGE ${hex(result.input_pressed,2)}`;
  const vram = unhex(result.vram), palette = result.palette;
  const image = $('screen').getContext('2d').createImageData(128,96);
  for (let i=0;i<128*96;i++) {
    const color = !result.display_enabled ? 0 : (vram[i>>1] >> ((i&1)*4)) & 15;
    const pixel = i * 4, entry = color * 3;
    image.data[pixel] = palette[entry];
    image.data[pixel + 1] = palette[entry + 1];
    image.data[pixel + 2] = palette[entry + 2];
    image.data[pixel + 3] = 255;
  }
  $('screen').getContext('2d').putImageData(image,0,0);
  $('palette').replaceChildren();
  for(let i=0;i<16;i++) {
    const swatch = document.createElement('span');
    swatch.style.backgroundColor = `rgb(${palette.slice(i*3,i*3+3).join(',')})`;
    swatch.title = `${i}: #${palette.slice(i*3,i*3+3).map(x=>hex(x,2)).join('')}`;
    $('palette').append(swatch);
  }
  let memory = '';
  for(let row=0;row<result.memory.length;row+=16) {
    const bytes = result.memory.slice(row,row+16);
    memory += `${hex(result.memory_address+row)}  ${bytes.map(x=>x===null?'??':hex(x,2)).join(' ')}  ${bytes.map(x=>x!==null && x>=32 && x<127?String.fromCharCode(x):'·').join('')}\n`;
  }
  $('memory').textContent = memory;
  renderAudio(result.audio,s);
  if (s.trapped) $('diagnostics').textContent = `Trap: ${s.trap.kind} at 0x${hex(s.trap.pc)} · ${s.trap.access} 0x${hex(s.trap.address)}`;
  updateEditor();
}
function renderAudio(audio, state) {
  $('listen').disabled = !audio;
  $('wav').disabled = !audio || !audio.pcm.length;
  const canvas = $('scope'), ctx = canvas.getContext('2d');
  ctx.clearRect(0,0,canvas.width,canvas.height);
  ctx.strokeStyle = '#34454d';
  ctx.beginPath();
  ctx.moveTo(0,50);
  ctx.lineTo(600,50);
  ctx.stroke();
  $('voices').replaceChildren();
  if (!audio) {
    $('audio-status').textContent='Profile 1 · no audio hardware';
    $('irq').textContent='Timer and interrupts are available in Profile 2.';
    return;
  }
  $('audio-status').textContent = `48 kHz · PCM16 mono · ${state.audio_samples.toLocaleString()} samples · ${audio.completed_frame ? 'last completed frame' : 'current partial frame'} (${audio.pcm.length})`;
  for(const [i,voice] of audio.voices.entries()) {
    const cell = document.createElement('div'), title = document.createElement('b'), text = document.createElement('div');
    title.textContent = `VOICE ${i+1} · ${voice.enabled?'ON':'OFF'}`;
    text.textContent = `${['SQUARE','SAW','TRIANGLE','NOISE'][voice.wave]} · ${voice.volume}/255`;
    const frequency = document.createElement('div');
    frequency.textContent = voice.wave===3 ? `LFSR ${hex(voice.noise)}` : `${(voice.step*48000/4294967296).toFixed(1)} Hz`;
    cell.append(title,text,frequency);
    $('voices').append(cell);
  }
  $('irq').textContent = `IRQ IE ${state.irq_ie?1:0} · pending ${state.irq_pending} · mask ${state.irq_mask} · depth ${state.irq_depth}\nTimer ${state.timer_remaining} / ${state.timer_period} · ${state.transition_slots.toLocaleString()} slots`;
  if(audio.pcm.length) {
    ctx.strokeStyle = '#a1edbc';
    ctx.lineWidth=1.2;
    ctx.beginPath();
    audio.pcm.forEach((sample,i) => {
      const x=i*600/Math.max(1,audio.pcm.length-1), y=50-sample/32768*45;
      if(i)ctx.lineTo(x,y);
      else ctx.moveTo(x,y);
    });
    ctx.stroke();
  }
  if(sound && running && audio.completed_frame && sound.state==='running') {
    // Host playback only queues the native integer PCM; it never synthesizes notes
    // or advances the machine clock. Drop lag instead of building an audio backlog.
    if (audioTime > sound.currentTime+0.15) return;
    const buffer=sound.createBuffer(1,audio.pcm.length,48000);
    buffer.copyToChannel(Float32Array.from(audio.pcm,x=>x/32768),0);
    const node=sound.createBufferSource();
    node.buffer=buffer;
    node.connect(sound.destination);
    audioNodes.add(node);
    node.onended=()=>audioNodes.delete(node);
    audioTime=Math.max(audioTime,sound.currentTime+0.01);
    node.start(audioTime);
    audioTime+=buffer.duration;
  }
}
const highlight = document.createElement('pre');
highlight.id='syntax';
highlight.setAttribute('aria-hidden','true');
$('source').before(highlight);
function updateEditor() {
  const source=$('source').value;
  const line=sourceMatches&&current?.source?.file==='main.n16c'?current.source.line:0;
  if (source === highlightedSource && line === highlightedLine) {
    syncScroll();
    return;
  }
  highlightedSource = source;
  highlightedLine = line;
  const escape=text=>text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  let output='',last=0;
  const pattern=/(\/\/[^\n]*|\b(?:fn|var|const|return|if|else|while|break|continue|true|false)\b|\b(?:u16|i16|bool|void)\b|\b(?:0x[\da-fA-F]+|\d+)\b)/g;
  for(const match of source.matchAll(pattern)) {
    output+=escape(source.slice(last,match.index));
    const word=match[0],cls=word.startsWith('//')?'comment':/^(u16|i16|bool|void)$/.test(word)?'type':/^\d/.test(word)?'number':'keyword';
    output+=`<span class="${cls}">${escape(word)}</span>`;
    last=match.index+word.length;
  }
  highlight.innerHTML=output+escape(source.slice(last))+'\n';
  $('line-numbers').innerHTML=source.split('\n').map((_,i)=>`<span class="${i+1===line?'current-line':''}">${i+1}</span>`).join('\n');
  syncScroll();
}
function syncScroll() {
  highlight.scrollTop=$('source').scrollTop;
  highlight.scrollLeft=$('source').scrollLeft;
  $('line-numbers').scrollTop=$('source').scrollTop;
}
$('source').oninput=()=> {
  sourceMatches=false;
  $('source-status').textContent='UNBUILT CHANGES';
  updateEditor();
};
$('source').onscroll=syncScroll;
$('source').onkeydown=event=> {
  if(event.key==='Tab') {
    event.preventDefault();
    const el=event.target,start=el.selectionStart;
    el.setRangeText('    ',start,el.selectionEnd,'end');
    el.dispatchEvent(new Event('input'));
  }
};
function fitScreen() {
  const box=$('screen-surround');
  const scale=$('integer-scale').checked?Math.max(1,Math.floor(Math.min((box.clientWidth-36)/128,(box.clientHeight-36)/96))):Math.min((box.clientWidth-36)/128,(box.clientHeight-36)/96);
  $('screen').style.width=`${128*scale}px`;
  $('screen').style.height=`${96*scale}px`;
}
new ResizeObserver(fitScreen).observe($('screen-surround'));
$('integer-scale').onchange=fitScreen;
$('screen').onpointermove=event=> {
  if(!current)return;
  const rect=event.target.getBoundingClientRect(),x=Math.min(127,Math.max(0,Math.floor((event.clientX-rect.left)*128/rect.width))),y=Math.min(95,Math.max(0,Math.floor((event.clientY-rect.top)*96/rect.height)));
  const byte=parseInt(current.vram.slice((y*64+(x>>1))*2,(y*64+(x>>1))*2+2),16),color=(byte>>((x&1)*4))&15;
  $('pixel-info').textContent=`(${x}, ${y}) · VRAM ${hex(0xc000+y*64+(x>>1))} · color ${color}`;
};
$('run').onclick = async () => {
  if (running) {
    pause();
    return;
  }
  running = true;
  const generation = ++runGeneration;
  $('run').textContent = 'Ⅱ Pause';
  try {
    while (running && generation === runGeneration) {
      const time = performance.now();
      const result = await vm({
        op: 'frame'
      });
      if (generation !== runGeneration) break;
      if (result.stopped || !result.ok) {
        pause();
        break;
      }
      await new Promise(resolve => setTimeout(resolve, Math.max(0, 16.67 - (performance.now() - time))));
    }
  } catch (_) {
    if (generation === runGeneration) pause();
  }
};
$('reset').onclick=()=>action('reset').catch(()=> {
});
$('reverse').onclick=()=>action('reverse').catch(()=> {
});
$('step').onclick=()=>action('step').catch(()=> {
});
$('next').onclick=()=>action('next').catch(()=> {
});
$('frame').onclick=()=> {
  pause();
  vm({
    op:'frame'
  }).catch(()=> {
  });
};
$('load').onclick=async()=> {
  pause();
  sourceMatches=false;
  const r=await api({
    op:'load',demo:$('demos').value
  }).catch(()=>null);
  if(r) {
    romBytes=null;
    $('download-rom').disabled=true;
    $('diagnostics').textContent='ROM loaded. Focus the display to use controller keys.';
  }
};
$('demos').onchange=()=> { $('edit-demo').disabled=!typedDemos[$('demos').value]; };
$('edit-demo').onclick=async()=> {
  if (!confirm('Replace the editor with this demo source? Save any edits first.')) return;
  pause();
  const result=await api({op:'edit_demo',demo:$('demos').value});
  $('source').value=result.editor_source;
  $('build-architecture').value=result.editor_architecture;
  $('build-optimization').value=result.editor_optimization;
  sourceMatches=false;
  $('source-status').textContent='SOURCE OPENED · BUILD TO RUN';
  updateEditor();
};
for (const id of ['build-architecture','build-optimization']) $(id).onchange=()=> {
  sourceMatches=false;
  $('source-status').textContent='UNBUILT CHANGES';
  updateEditor();
};
$('build').onclick = async () => {
  pause();
  $('build').disabled = true;
  const builtSource = $('source').value;
  const builtArchitecture = $('build-architecture').value;
  const builtOptimization = $('build-optimization').value;
  try {
    const result = await api({
      op: 'build', source: builtSource,
      architecture: builtArchitecture, optimization: builtOptimization
    });
    $('diagnostics').classList.toggle('error', !result.ok);
    if (result.ok) {
      sourceMatches = $('source').value === builtSource && $('build-architecture').value === builtArchitecture && $('build-optimization').value === builtOptimization;
      romBytes = unhex(result.rom);
      $('download-rom').disabled = false;
      $('source-status').textContent = sourceMatches ? 'BUILD SUCCEEDED' : 'UNBUILT CHANGES';
      $('diagnostics').textContent = `Build succeeded · ${result.size_report.rom_payload_bytes} / 8192 ROM bytes · ${result.size_report.removed_library_blocks} unused library blocks removed`;
    } else {
      $('diagnostics').textContent = result.diagnostics || result.error;
      $('source-status').textContent = 'BUILD FAILED';
    }
    updateEditor();
  }
  finally {
    $('build').disabled = false;
  }
};
$('download-source').onclick=()=>download('main.n16c',$('source').value,'text/plain');
$('download-rom').onclick=()=>romBytes&&download('program.n16',romBytes,'application/octet-stream');
$('command-form').onsubmit=event=> {
  event.preventDefault();
  const command=$('command').value.trim();
  if(command) {
    log(`n16> ${command}`);
    $('command').value='';
    action(command).catch(()=> {
    });
  }
};
$('break-form').onsubmit=event=> {
  event.preventDefault();
  action(`break ${$('break-address').value.trim()}`).catch(()=> {
  });
};
function inspect(value) {
  const n=Number(value);
  if(!Number.isInteger(n)||n<0||n>0xff00) {
    log('Memory address must be 0x0000–0xFF00');
    return;
  }
  address=n;
  $('memory-address').value='0x'+hex(n);
  vm({
    op:'observe'
  }).catch(()=> {
  });
}
$('memory-form').onsubmit=event=> {
  event.preventDefault();
  inspect($('memory-address').value);
};
document.querySelectorAll('[data-address]').forEach(button=>button.onclick=()=>inspect(button.dataset.address));
for(const name of ['memory','audio'])$(name+'-tab').onclick=()=> {
  for(const tab of ['memory','audio']) {
    $(tab+'-tab').setAttribute('aria-selected',String(tab===name));
    $(tab+'-panel').hidden=tab!==name;
  }
};
function input(bit,down) {
  const next=down?held|bit:held&~bit;
  if(next===held)return;
  held=next;
  document.querySelectorAll('[data-bit]').forEach(button=>button.classList.toggle('active',Boolean(held&Number(button.dataset.bit))));
  vm({
    op:'command',command:`input ${held}`
  }).catch(()=> {
  });
}
const keyBits= {
  ArrowUp:1,ArrowDown:2,ArrowLeft:4,ArrowRight:8,KeyZ:16,KeyX:32,Enter:64,ShiftLeft:128,ShiftRight:128
};
const pressedKeys=new Set();
window.addEventListener('keydown',event=> {
  if(event.key==='F5') {
    event.preventDefault();
    $('run').click();
  } else if(event.key==='F10') {
    event.preventDefault();
    $('step').click();
  }
  if(document.activeElement!==$('screen'))return;
  const bit=keyBits[event.code];
  if(bit) {
    event.preventDefault();
    pressedKeys.add(event.code);
    input(bit,true);
  }
});
window.addEventListener('keyup',event=> {
  if(!pressedKeys.has(event.code))return;
  pressedKeys.delete(event.code);
  if(![...pressedKeys].some(code=>keyBits[code]===keyBits[event.code]))input(keyBits[event.code],false);
});
function releaseInput() {
  pressedKeys.clear();
  if(held) {
    held=0;
    document.querySelectorAll('[data-bit]').forEach(button=>button.classList.remove('active'));
    vm({
      op:'command',command:'input 0'
    }).catch(()=> {
    });
  }
}
window.addEventListener('blur',()=> {
  pause();
  releaseInput();
});
document.addEventListener('visibilitychange',()=> {
  if(document.hidden) {
    pause();
    releaseInput();
  }
});
$('screen').addEventListener('blur',releaseInput);
document.querySelectorAll('[data-bit]').forEach(button=> {
  button.onpointerdown=event=> {
    event.preventDefault();
    button.setPointerCapture(event.pointerId);
    input(Number(button.dataset.bit),true);
  };
  button.onpointerup=()=>input(Number(button.dataset.bit),false);
  button.onpointercancel=()=>input(Number(button.dataset.bit),false);
});
$('save-snapshot').onclick=async()=> {
  pause();
  const r=await vm({
    op:'snapshot'
  });
  if(r.ok)download('machine.n16s',unhex(r.snapshot),'application/octet-stream');
};
$('restore-snapshot').onclick=()=> {
  pause();
  $('snapshot-file').click();
};
$('snapshot-file').onchange=async()=> {
  const file=$('snapshot-file').files[0];
  if(!file)return;
  if(file.size>67680) {
    log('Snapshot exceeds 67,680 bytes');
    return;
  }
  const data=[...new Uint8Array(await file.arrayBuffer())].map(x=>hex(x,2)).join('');
  await vm({
    op:'restore',data
  });
  $('snapshot-file').value='';
};
$('replay').onclick=()=> {
  pause();
  $('replay-dialog').showModal();
};
$('replay-cancel').onclick=()=>$('replay-dialog').close();
$('replay-start').onclick=async()=> {
  $('replay-dialog').close();
  held=0;
  await api({
    op:'replay',frames:Number($('replay-frames').value),schedule:$('schedule').value
  }).catch(()=> {
  });
};
$('listen').onclick=async()=> {
  if(sound) {
    stopSound();
    await sound.close();
    sound=null;
    $('listen').textContent='Enable sound';
  } else {
    sound=new AudioContext({
      sampleRate:48000
    });
    await sound.resume();
    $('listen').textContent='Mute sound';
  }
};
$('wav').onclick=()=> {
  const pcm=current?.audio?.pcm;
  if(!pcm?.length)return;
  const bytes=new ArrayBuffer(44+pcm.length*2),view=new DataView(bytes),text=(offset,value)=>[...value].forEach((c,i)=>view.setUint8(offset+i,c.charCodeAt(0)));
  text(0,'RIFF');
  view.setUint32(4,36+pcm.length*2,true);
  text(8,'WAVEfmt ');
  view.setUint32(16,16,true);
  view.setUint16(20,1,true);
  view.setUint16(22,1,true);
  view.setUint32(24,48000,true);
  view.setUint32(28,96000,true);
  view.setUint16(32,2,true);
  view.setUint16(34,16,true);
  text(36,'data');
  view.setUint32(40,pcm.length*2,true);
  pcm.forEach((x,i)=>view.setInt16(44+i*2,x,true));
  download('nova-frame.wav',bytes,'audio/wav');
};
api({
  op:'bootstrap'
}).then(result=> {
  $('source').value=result.editor_source;
  typedDemos=result.typed_demos;
  $('build-architecture').value=result.editor_architecture;
  $('build-optimization').value=result.editor_optimization;
  for(const [id,title]of Object.entries(result.demos)) {
    const option=document.createElement('option');
    option.value=id;
    option.textContent=title;
    $('demos').append(option);
  }
  $('edit-demo').disabled=!typedDemos[$('demos').value];
  updateEditor();
}).catch(()=> {
  $('connection').textContent='SESSION UNAVAILABLE';
  log('Open the full local URL printed by scripts/workbench.py to connect.');
});
// Event promises terminate here, including browser audio/file API failures.
for (const [id, event] of [['load','onclick'], ['build','onclick'], ['edit-demo','onclick'],
['save-snapshot','onclick'], ['snapshot-file','onchange'],
['listen','onclick'], ['replay-start','onclick']]) {
  const handler = $(id)[event];
  $(id)[event] = (...args) => Promise.resolve().then(() => handler(...args))
  .catch(error => {
    log(error.message);
    pause();
  });
}

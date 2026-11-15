// Inlined by package_web.py. The Worker owns all VM/compiler state; this side
// only transports bounded requests. No fetch, CDN or host synthesis is needed.
(() => {
  window.NovaOfflineRequest=()=>Promise.reject(Error('Offline VM initialization failed; this browser must support WebAssembly and Workers.'));
  const data=JSON.parse(document.getElementById('nova-assets').textContent);
  const code='const DATA='+JSON.stringify(data)+';\n'+__NOVA_WORKER_SOURCE__;
  const url=URL.createObjectURL(new Blob([code],{type:'text/javascript'}));
  let worker;
  try {worker=new Worker(url);} catch(error) {URL.revokeObjectURL(url);throw error;}
  const pending=new Map();
  let next=0, fatal=null, revoked=false;
  function revoke() {
    if(!revoked) {URL.revokeObjectURL(url);revoked=true;}
  }
  function dispose(message) {
    if(fatal)return;
    fatal=Error(message);
    revoke();
    worker.terminate();
    for(const job of pending.values()) {
      clearTimeout(job.timer);
      job.reject(fatal);
    }
    pending.clear();
  }
  worker.onmessage=event=> {
    revoke();
    const {id,response}=event.data??{};
    const job=pending.get(id);
    if(!job)return;
    if(!response || !Number.isInteger(response.status) || response.status<100 || response.status>599 ||
        !response.result || typeof response.result!=='object' || Array.isArray(response.result)) {
      dispose('Offline VM returned an invalid response');
      return;
    }
    pending.delete(id);
    clearTimeout(job.timer);
    job.resolve({ok:response.status>=200&&response.status<300,json:async()=>response.result});
  };
  worker.onerror=()=>dispose('Offline VM Worker failed');
  worker.onmessageerror=()=>dispose('Offline VM response could not be decoded');
  window.NovaOfflineRequest=payload=> {
    if(fatal)return Promise.reject(fatal);
    if(pending.size>=16)return Promise.reject(Error('Offline VM request queue is full'));
    return new Promise((resolve,reject)=> {
      const id=++next;
      const timer=setTimeout(()=>dispose('Offline VM exceeded its 20-second response budget'),20000);
      pending.set(id,{resolve,reject,timer});
      try {worker.postMessage({id,payload});} catch(error) {
        pending.delete(id);
        clearTimeout(timer);
        reject(error);
      }
    });
  };
  // A bfcache return gets a fresh Worker and bootstrap instead of a dead session.
  window.addEventListener('pagehide',()=>dispose('Offline VM page closed'));
  window.addEventListener('pageshow',event=> {if(event.persisted)location.reload();});
})();

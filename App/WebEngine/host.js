// WebKit owns the audio path. Swift receives display/state/flash only, never PCM.
'use strict';
(() => {
  const send=value=>window.webkit?.messageHandlers?.fm1?.postMessage(value);
  const encodeError=error=>error?.message||String(error);
  let worker=null, context=null, node=null, generation=0, request=0, muted=false;
  let failureSerial=0;
  let state=0, serial=Promise.resolve(), audioDiagnostics={}, engineDiagnostics={};
  const pending=new Map(), resets=new Map();
  let primedGeneration=-1, primedWaiter=null, startedGeneration=-1, startedWaiter=null;
  const mergeDiagnostics=(engine=engineDiagnostics)=>({...engine,...audioDiagnostics,inputSampleRate:44100,
    audioContextSampleRate:context?.sampleRate||0,counterScope:'engine-instance-lifetime',
    outputCounterElapsedSeconds:(audioDiagnostics.outputRequestedFrames||0)/(context?.sampleRate||44100)});
  const metrics=()=>mergeDiagnostics();
  function normalizeResult(result) {
    if(result?.flashBytes===undefined)return result;
    const bytes=result.flashBytes;
    if(!(bytes instanceof ArrayBuffer)||bytes.byteLength!==1048576)throw Error('engine returned an invalid flash snapshot');
    const view=new Uint8Array(bytes);let text='';
    for(let i=0;i<view.length;i+=8192)text+=String.fromCharCode(...view.subarray(i,i+8192));
    const {flashBytes,...rest}=result;return {...rest,flash:btoa(text)};
  }
  function bounded(promise,milliseconds,stage) {
    let timer;return Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error(stage+' timed out')),milliseconds)})]).finally(()=>clearTimeout(timer));
  }
  const stage=value=>send({kind:'diagnostics',...metrics(),stage:value,audioContextState:context?.state||'absent'});
  function rejectPending(error) {
    for(const p of pending.values()){clearTimeout(p.timer);p.reject(error)}pending.clear();
    for(const p of resets.values()){clearTimeout(p.timer);p.reject(error)}resets.clear();
    if(primedWaiter){clearTimeout(primedWaiter.timer);primedWaiter.reject(error);primedWaiter=null}
    if(startedWaiter){clearTimeout(startedWaiter.timer);startedWaiter.reject(error);startedWaiter=null}
  }
  function failure(error) {
    state=2;failureSerial++;
    node?.port.postMessage({kind:'active',generation,active:false});
    context?.suspend().catch(()=>{});
    send({kind:'failure',error:encodeError(error)});
  }
  function rpc(op,args={},transfer=[]) {
    if(!worker)return Promise.reject(Error('engine not loaded'));
    const id=++request;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{pending.delete(id);reject(Error(op+' timed out'))},12000);
      pending.set(id,{resolve,reject,timer});worker.postMessage({id,op,...args},transfer);
    });
  }
  function reset(wait=true) {
    const id=++request;generation++;primedGeneration=-1;startedGeneration=-1;
    if(!wait){node.port.postMessage({kind:'reset',id,generation});return Promise.resolve()}
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{resets.delete(id);reject(Error('audio flush timed out'))},5000);
      resets.set(id,{resolve,reject,timer});
      node.port.postMessage({kind:'reset',id,generation});
    });
  }
  function waitPrimed() {
    if(primedGeneration===generation)return Promise.resolve();
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{primedWaiter=null;reject(Error('audio queue prefill timed out'))},5000);
      primedWaiter={resolve,reject,timer};
    });
  }
  function waitStarted() {
    if(startedGeneration===generation)return Promise.resolve();
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{startedWaiter=null;reject(Error('audio output start timed out'))},5000);
      startedWaiter={resolve,reject,timer};
    });
  }
  async function dispose() {
    state=0;worker?.terminate();worker=null;
    rejectPending(Error('engine closed'));
    node?.disconnect();node=null;
    if(context){await bounded(context.close(),5000,'audio close');context=null}
    audioDiagnostics={};engineDiagnostics={};
  }
  async function command(m) {
    switch(m.op) {
    case 'load': {
      const deadline=Date.now()+12000;
      const remaining=()=>Math.max(1,deadline-Date.now());
      await dispose();generation=0;
      const Audio=window.AudioContext||window.webkitAudioContext;
      if(!Audio)throw Error('AudioContext unavailable');
      context=new Audio({sampleRate:44100,latencyHint:'interactive'});
      await bounded(context.audioWorklet.addModule('pcm-worklet.js'),Math.min(5000,remaining()),'audio module load');
      node=new AudioWorkletNode(context,'fm1-pcm',{numberOfInputs:0,numberOfOutputs:1,outputChannelCount:[2]});
      node.onprocessorerror=()=>failure(Error('audio processor failed'));
      node.connect(context.destination);
      const channel=new MessageChannel();
      node.port.onmessage=e=>{const v=e.data;
        if(v.kind==='reset'){const p=resets.get(v.id);if(p){clearTimeout(p.timer);resets.delete(v.id);p.resolve()}}
        else if(v.kind==='primed'&&v.generation===generation){primedGeneration=generation;if(primedWaiter){clearTimeout(primedWaiter.timer);primedWaiter.resolve();primedWaiter=null}}
        else if(v.kind==='started'&&v.generation===generation&&v.deliveredFrames>0){startedGeneration=generation;if(startedWaiter){clearTimeout(startedWaiter.timer);startedWaiter.resolve();startedWaiter=null}}
        else if(v.kind==='diagnostics'){audioDiagnostics=v;delete audioDiagnostics.kind;send({kind:'diagnostics',...metrics()})}
        else if(v.kind==='failure')failure(v.error);
      };
      node.port.postMessage({kind:'connect',port:channel.port1},[channel.port1]);
      worker=new Worker('engine-worker.js');const current=worker;
      worker.onmessage=e=>{if(worker!==current)return;const v=e.data;
        if(v.kind==='reply'){const p=pending.get(v.id);if(p){clearTimeout(p.timer);pending.delete(v.id);if(v.ok){try{p.resolve(normalizeResult(v.result))}catch(error){p.reject(error)}}else p.reject(Error(v.error))}}
        else if(v.kind==='diagnostics'){engineDiagnostics=v;delete engineDiagnostics.kind;send({kind:'diagnostics',...metrics()})}
        else if(v.kind==='snapshot')send({...v,state});
        else if(v.kind==='failure')failure(v.error);
      };
      worker.onerror=e=>{if(worker!==current)return;const error=Error(e.message||'engine worker failed');rejectPending(error);failure(error)};
      worker.onmessageerror=()=>{if(worker===current)failure(Error('unreadable worker message'))};
      const result=await bounded(rpc('load',{packageURL:m.packageURL,flashURL:m.flashURL,
        expectedModuleSHA256:m.expectedModuleSHA256,sampleRate:m.sampleRate,guestHz:m.guestHz,port:channel.port2},[channel.port2]),remaining(),'engine load');
      state=0;return {...result,outputSampleRate:context.sampleRate};
    }
    case 'play': {
      if(!context||!node)throw Error('engine not loaded');
      if(state===1)return {state:1,diagnostics:metrics()};
      const startFailureSerial=failureSerial;
      const deadline=Date.now()+12000;
      const remaining=()=>Math.max(1,deadline-Date.now());
      stage('resume-start');
      await bounded(context.resume(),Math.min(5000,remaining()),'audio resume');stage('resume-done');
      if(context.state!=='running')throw Error('audio context did not start: '+context.state);
      await bounded(reset(),remaining(),'audio reset');stage('reset-done');
      node.port.postMessage({kind:'mute',generation,muted});
      const result=await bounded(rpc('play',{generation}),remaining(),'producer prefill');stage('producer-prefill-done');
      await bounded(waitPrimed(),remaining(),'audio prefill');stage('prefill-done');
      if(failureSerial!==startFailureSerial)throw Error('audio engine failed during start');
      if(context.state!=='running'){await bounded(rpc('pause'),remaining(),'producer stop');throw Error('audio context stopped during start: '+context.state)}
      node.port.postMessage({kind:'active',generation,active:true});
      await bounded(waitStarted(),remaining(),'audio output start');stage('output-started');
      if(failureSerial!==startFailureSerial||context.state!=='running')throw Error('audio stopped before start confirmation');
      state=1;
      engineDiagnostics=result.diagnostics;
      return {...result,diagnostics:mergeDiagnostics(result.diagnostics)};
    }
    case 'pause': {
      if(!context||!node)throw Error('engine not loaded');
      node.port.postMessage({kind:'active',generation,active:false});
      const result=await rpc('pause');
      // A running context lets its worklet acknowledge a complete flush before suspend.
      // An already suspended/interrupted context cannot output; still invalidate its queue
      // immediately, with the flush acknowledgement deferred until it can process messages.
      await reset(context.state==='running');
      await bounded(context.suspend(),5000,'audio suspend');state=0;
      return {...result,diagnostics:mergeDiagnostics(result.diagnostics)};
    }
    case 'flash': {const result=await rpc('flash');return {...result,diagnostics:mergeDiagnostics(result.diagnostics)}}
    case 'mute':muted=!!m.muted;node?.port.postMessage({kind:'mute',generation,muted});return {};
    case 'close':await dispose();return {};
    case 'key':return rpc('key',{key:m.key,down:!!m.down});
    case 'releaseAll':return rpc('releaseAll');
    case 'encoder':return rpc('encoder',{encoder:m.encoder,delta:m.delta});
    case 'master':return rpc('master',{value:m.value});
    default:throw Error('unknown operation');
    }
  }
  window.FM1Host={command(m) {
    // Preserve command order through async load/play/pause. Every operation gets a reply.
    serial=serial.catch(()=>{}).then(async()=>{
      try{const result=await command(m);send({kind:'reply',id:m.id,ok:true,result})}
      catch(error){if(m.op==='load'||m.op==='play')failure(error);send({kind:'reply',id:m.id,ok:false,error:encodeError(error)})}
    });
    return true;
  }};
  send({kind:'ready'});
})();

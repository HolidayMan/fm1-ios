// Actual firmware execution and generated WASM module compilation belong exclusively
// to this dedicated worker. The selected CPU clock is validated; audio stays at 44.1 kHz.
'use strict';
let x=null, pcm=null, playing=false, generation=0, outstanding=0, scheduled=false;
let guestMHz=240, renderBudget=4800000;
let stats={}, lastSnapshot=0, lastDiagnostics=0, lcdRevision=null;
const keys=new Set();
const recentRenderMs=new Float64Array(128);let recentCount=0,recentWrite=0;
const PIN='d3f51e1b50fd90c5be186f592c52a04139faceb5fbefd41c248790e620620c87';
const tailCallProbe=()=>{try{const bytes=new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,96,0,1,127,3,3,2,0,0,4,4,1,112,0,1,7,9,1,5,112,114,111,98,101,0,1,9,7,1,0,65,0,11,1,0,10,14,2,4,0,65,7,11,7,0,65,0,19,0,0,11]);return WebAssembly.validate(bytes)&&new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports.probe()===7}catch{return false}};
const CHUNK=512, CAPACITY=2048, PREFILL=1536;
const CLOCKS=[120,180,240,320,360];
const emit=(value,transfer=[])=>postMessage(value,transfer);
const reply=(id,result)=>emit({kind:'reply',id,ok:true,result},result?.flashBytes instanceof ArrayBuffer?[result.flashBytes]:[]);
const fail=(id,error)=>emit({kind:'reply',id,ok:false,error:String(error)});
const bytesToBase64=bytes=>{let s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s)};
const copy=bytes=>{const p=x.fm1_alloc(bytes.byteLength);new Uint8Array(x.memory.buffer,p,bytes.byteLength).set(new Uint8Array(bytes));return p};
const releaseAll=()=>{for(const key of keys)x.fm1_key(key,0);keys.clear()};
const diagnostics=()=>{const recent=Array.from(recentRenderMs.subarray(0,recentCount)).sort((a,b)=>a-b);return {...stats,
  renderRatioMean:stats.requestedFrames?stats.renderTotalMs/(stats.requestedFrames/44.1):0,
  renderRatioP95:recent.length?recent[Math.ceil(recent.length*.95)-1]/(CHUNK/44.1):null,
  renderRatioP95Available:recent.length>0,renderRatioMax:stats.renderMaxMs/(CHUNK/44.1),
  renderChunkFrames:CHUNK,counterScope:'engine-instance-lifetime',guestHz:guestMHz*1000000,inputSampleRate:44100,emulatedMs:x?.fm1_ms()||0,
  queuedInputFrames:outstanding,memoryBytes:x?.memory.buffer.byteLength||0,tableSlots:x?.__indirect_function_table.length||0}};
const flash=()=>{const n=x.fm1_flash_len();if(n!==1048576)throw Error('invalid flash length');return new Uint8Array(x.memory.buffer,x.fm1_flash_ptr(),n).slice().buffer};
function snapshot(force=false) {
  const now=performance.now(); if(!force && now-lastSnapshot<100)return;
  lastSnapshot=now;
  const revision=x.fm1_lcd_revision();let pixels=null;
  if(force||revision!==lcdRevision) {
    lcdRevision=revision; const input=new Uint16Array(x.memory.buffer,x.fm1_lcd(),240*240);
    const rgba=new Uint8Array(240*240*4);
    for(let i=0;i<input.length;i++) {const p=input[i],j=i*4;
      rgba[j]=Math.round(((p>>>11)&31)*255/31);rgba[j+1]=Math.round(((p>>>5)&63)*255/63);
      rgba[j+2]=Math.round((p&31)*255/31);rgba[j+3]=255;}
    pixels=bytesToBase64(rgba);
  }
  emit({kind:'snapshot',pixels,leds:Array.from(new Float32Array(x.memory.buffer,x.fm1_leds(),41)),state:playing?1:0});
  if(now-lastDiagnostics>=1000){lastDiagnostics=now;emit({kind:'diagnostics',...diagnostics()})}
}
function renderChunk() {
  const start=performance.now(),have=x.fm1_render(CHUNK,renderBudget);
  const inputL=new Float32Array(x.memory.buffer,x.fm1_out_l(),CHUNK);
  const inputR=new Float32Array(x.memory.buffer,x.fm1_out_r(),CHUNK);
  const left=new Float32Array(CHUNK),right=new Float32Array(CHUNK);
  for(let i=0;i<CHUNK;i++){
    left[i]=inputL[i];right[i]=inputR[i];
    if(i<have){
      if(left[i]!==0)stats.nonzeroInputSamples++;if(right[i]!==0)stats.nonzeroInputSamples++;
      stats.peakAbsoluteSample=Math.max(stats.peakAbsoluteSample,Math.abs(left[i]),Math.abs(right[i]));
    }
  }
  stats.renderCalls++;stats.renderedFrames+=have;stats.requestedFrames+=CHUNK;
  const elapsed=performance.now()-start;
  stats.missingCoreFrames+=CHUNK-have;stats.renderTotalMs+=elapsed;
  stats.renderMaxMs=Math.max(stats.renderMaxMs,elapsed);
  recentRenderMs[recentWrite]=elapsed;recentWrite=(recentWrite+1)%128;recentCount=Math.min(128,recentCount+1);
  if(x.fm1_halted())throw Error('firmware halted');
  outstanding+=CHUNK;pcm.postMessage({kind:'pcm',generation,left,right},[left.buffer,right.buffer]);
}
function schedule() {
  if(scheduled||!playing||outstanding+CHUNK>CAPACITY)return;
  scheduled=true;const scheduledGeneration=generation;
  setTimeout(()=>{scheduled=false;if(scheduledGeneration!==generation){schedule();return}if(!playing||outstanding+CHUNK>CAPACITY)return;
    try{renderChunk();snapshot();schedule()}catch(error){playing=false;emit({kind:'failure',error:String(error)});}
  },0);
}
async function load(m) {
  if(!Number.isInteger(m.guestHz)||!CLOCKS.includes(m.guestHz/1000000)||m.sampleRate!==44100)throw Error('unsupported guest clock or input sample rate');
  guestMHz=m.guestHz/1000000;renderBudget=guestMHz*20000;
  if(m.expectedModuleSHA256!==PIN)throw Error('unexpected engine pin');
  const base=new URL('.',location.href);
  const get=async url=>{const u=new URL(url,base);if(u.origin!==base.origin||!u.pathname.startsWith(base.pathname))throw Error('resource outside session');
    const r=await fetch(u.href,{cache:'no-store'});if(!r.ok)throw Error('resource fetch '+r.status);return r.arrayBuffer()};
  const [wasm,pkg,initial]=await Promise.all([get('engine.wasm'),get(m.packageURL),m.flashURL?get(m.flashURL):null]);
  const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',wasm)),b=>b.toString(16).padStart(2,'0')).join('');
  if(hash!==PIN)throw Error('engine SHA-256 mismatch');
  if(pkg.byteLength<960||pkg.byteLength>4*1024*1024)throw Error('invalid package size');
  recentCount=recentWrite=0;
  stats={nonzeroInputSamples:0,peakAbsoluteSample:0,regions:0,failed:0,compileMs:0,compileMaxMs:0,generatedBytes:0,renderCalls:0,renderedFrames:0,requestedFrames:0,missingCoreFrames:0,renderTotalMs:0,renderMaxMs:0};
  const imports={fm1_jit_compile:(ptr,len)=>{const start=performance.now();try{
    const bytes=new Uint8Array(x.memory.buffer,ptr,len).slice(),table=x.__indirect_function_table;
    const run=new WebAssembly.Instance(new WebAssembly.Module(bytes),{env:{memory:x.memory,table}}).exports.run;
    const slot=table.grow(1);table.set(slot,run);stats.regions++;stats.generatedBytes+=len;return slot;
  }catch(error){stats.failed++;stats.lastCompileError=String(error);return 0}
  finally{const elapsed=performance.now()-start;stats.compileMs+=elapsed;stats.compileMaxMs=Math.max(stats.compileMaxMs,elapsed)}}};
  x=(await WebAssembly.instantiate(wasm,{env:imports})).instance.exports;
  // The same execution probe used by the accepted research harness.
  stats.tailCallsSupported=tailCallProbe();
  x.fm1_acceleration_tailcalls?.(stats.tailCallsSupported?1:0);x.fm1_jit(1,16);
  if(x.fm1_boot_fwsc(copy(pkg),pkg.byteLength,0,0,guestMHz))throw Error('FWSC boot rejected');
  if(x.fm1_board()!==0)throw Error('package is not FM-1');
  if(initial){if(initial.byteLength!==1048576||x.fm1_flash_restore(copy(initial),initial.byteLength))throw Error('flash restore rejected');
    const actual=new Uint8Array(x.memory.buffer,x.fm1_flash_ptr(),x.fm1_flash_len()),expected=new Uint8Array(initial);
    if(actual.length!==expected.length||!actual.every((b,i)=>b===expected[i]))throw Error('flash restore mismatch');}
  pcm=m.port;pcm.onmessage=e=>{const v=e.data;if(v.kind==='consumed'&&v.generation===generation){outstanding=Math.max(0,outstanding-v.frames);schedule()}};pcm.start();
  playing=false;outstanding=0;keys.clear();lcdRevision=null;snapshot(true);
  return {state:0,diagnostics:diagnostics(),moduleSHA256:hash};
}
onmessage=async event=>{const m=event.data;try {
  let result={};
  if(m.op==='load')result=await load(m);
  else {if(!x)throw Error('engine not loaded');
    switch(m.op) {
    case 'play':
      generation=m.generation;outstanding=0;playing=true;
      // Yield between bounded chunks so keys/pause can enter the worker queue.
      for(let i=0;i<PREFILL/CHUNK&&playing&&outstanding+CHUNK<=CAPACITY;i++){renderChunk();await new Promise(r=>setTimeout(r,0))}
      schedule();snapshot(true);result={state:1,diagnostics:diagnostics()};break;
    case 'pause':playing=false;releaseAll();outstanding=0;snapshot(true);result={flashBytes:flash(),diagnostics:diagnostics()};break;
    case 'flash':result={flashBytes:flash(),diagnostics:diagnostics()};break;
    case 'key':if(!Number.isInteger(m.key)||m.key<0||m.key>40)throw Error('invalid key');x.fm1_key(m.key,m.down?1:0);if(m.down)keys.add(m.key);else keys.delete(m.key);break;
    case 'releaseAll':releaseAll();break;
    case 'encoder':if(!Number.isInteger(m.encoder)||m.encoder<0||m.encoder>6||!Number.isInteger(m.delta)||Math.abs(m.delta)>1024)throw Error('invalid encoder');x.fm1_enc(m.encoder,m.delta);break;
    case 'master':if(!Number.isInteger(m.value)||m.value<0||m.value>1023)throw Error('invalid master');x.fm1_pot(m.value);break;
    case 'close':playing=false;releaseAll();pcm?.close();x=null;break;
    default:throw Error('unknown operation');
    }
  }
  reply(m.id,result);
}catch(error){if(m.op==='load'||m.op==='play'){playing=false;emit({kind:'failure',error:String(error)})}fail(m.id,error)}};

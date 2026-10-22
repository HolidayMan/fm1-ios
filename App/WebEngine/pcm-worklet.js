// PCM consumption only. No WebAssembly, firmware, compilation or emulation here.
class FM1PCM extends AudioWorkletProcessor {
  constructor() {
    super();
    this.left = new Float32Array(2048); this.right = new Float32Array(2048);
    this.read = 0; this.write = 0; this.count = 0; this.phase = 0;
    this.generationDelivered = 0; this.started = false; this.primed = false; this.generation = 0; this.active = false; this.muted = false;
    this.ratio = 44100 / sampleRate; this.credit = 0;
    this.requested = 0; this.missing = 0; this.underflows = 0;
    this.lastL = 0; this.lastR = 0; this.fade = 0; this.report = 0;
    this.port.onmessage = e => {
      const m = e.data;
      if (m.kind === 'connect') {
        this.producer = m.port;
        this.producer.onmessage = event => this.receive(event.data);
        this.producer.start();
      } else if (m.kind === 'reset') {
        this.generation = m.generation; this.active = false; this.primed = false; this.started = false; this.generationDelivered = 0;
        this.read = this.write = this.count = this.phase = this.credit = 0;
        this.lastL = this.lastR = this.fade = 0;
        this.port.postMessage({kind:'reset', id:m.id});
      } else if (m.generation === this.generation) {
        if (m.kind === 'active') this.active = m.active;
        if (m.kind === 'mute') this.muted = m.muted;
      }
    };
  }
  receive(m) {
    if (m.generation !== this.generation || m.kind !== 'pcm') return;
    const n = m.left.length;
    if (n > 512 || n !== m.right.length || n > 2048 - this.count) {
      this.active = false;
      this.port.postMessage({kind:'failure', error:'PCM queue overflow or invalid chunk'});
      return;
    }
    for (let i=0;i<n;i++) {
      this.left[this.write] = m.left[i]; this.right[this.write] = m.right[i];
      this.write = (this.write + 1) & 2047;
    }
    this.count += n;
    if (!this.primed && this.count >= 1536) {
      this.primed = true; this.port.postMessage({kind:'primed', generation:this.generation});
    }
  }
  process(_inputs, outputs) {
    const out = outputs[0];
    if (!out || !out[0]) return true;
    const l = out[0], r = out[1] || out[0];
    let missing = false;
    for (let i=0;i<l.length;i++) {
      let a=0,b=0;
      if (this.active) {
        this.requested++;
        // Keep one look-ahead sample for linear sample-rate conversion.
        if (this.count >= 2) {
          this.generationDelivered++;
          const next=(this.read+1)&2047, f=this.phase;
          a=this.left[this.read]+(this.left[next]-this.left[this.read])*f;
          b=this.right[this.read]+(this.right[next]-this.right[this.read])*f;
          this.phase += this.ratio;
          while (this.phase >= 1 && this.count > 0) {
            this.phase--; this.read=(this.read+1)&2047; this.count--; this.credit++;
          }
          this.fade=Math.min(32,this.fade+1); a*=this.fade/32; b*=this.fade/32;
          this.lastL=a; this.lastR=b;
        } else {
          this.missing++; missing=true; this.fade=0; this.phase=0;
          this.lastL*=0.96; this.lastR*=0.96; a=this.lastL; b=this.lastR;
        }
      }
      l[i]=this.muted?0:a; r[i]=this.muted?0:b;
    }
    if (this.active && !this.started && this.generationDelivered > 0) {
      this.started=true;this.port.postMessage({kind:'started',generation:this.generation,
        deliveredFrames:this.generationDelivered,outputRequestedFrames:this.requested,outputUnderflowFrames:this.missing});
    }
    if (missing) this.underflows++;
    if (this.credit >= 256 && this.producer) {
      this.producer.postMessage({kind:'consumed', generation:this.generation, frames:this.credit});
      this.credit=0;
    }
    this.report += l.length;
    if (this.report >= sampleRate) {
      this.report=0;
      this.port.postMessage({kind:'diagnostics', outputSampleRate:sampleRate,
        outputRequestedFrames:this.requested, outputUnderflowFrames:this.missing,
        outputUnderflowCallbacks:this.underflows, queuedInputFrames:this.count});
    }
    return true;
  }
}
registerProcessor('fm1-pcm', FM1PCM);

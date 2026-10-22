# Experimental universal WASM mode

The native panel routes unmatched FWSC releases to a private WebKit engine. Five exact
releases also have source-native engines and a Native/WASM switch. This mode
uses the generic pi32v2 firmware translator; it has no firmware-specific block whitelist.
The guest clock defaults to 240 MHz; 120, 180, 320 and 360 MHz are selectable.
Its I2S stream stays at 44.1 kHz. Changing clocks checkpoints and restarts the
engine with the current Play/Pause intent. Lower rates can change firmware timing.

`App/WebEngine/engine-worker.js` boots the actual FWSC, restores its existing 1 MiB flash,
executes the CPU, and compiles generated WebAssembly modules on one dedicated Worker.
Each render requests 512 input frames with a budget of selected MHz × 20,000
(4.8 million at the unchanged default). The actual selected MHz reaches CPU boot.
The worker yields between chunks and stops producing at 2048 outstanding input frames
(46.44 ms). Starting playback primes 1536 frames (34.83 ms); the AudioWorklet confirms
receipt before output starts, and the first actual consumer callback must acknowledge
the playback generation before the host reports Running. Consumed-frame credits bound both in-flight messages and
the consumer queue. There is no emulation or WebAssembly compilation in the audio callback.

`pcm-worklet.js` consumes stereo PCM from a fixed 2048-frame ring and linearly resamples
44.1 kHz to the actual AudioContext sample rate. The worker reports render budget mean and the actual p95 of its most recent 128 chunks,
plus scalar nonzero-input-sample and peak-amplitude counters for actual WebKit note checks.
Its bounded callback counts missing output
frames, applies a short recovery fade, and posts batched refill credits. PCM stays within
WebKit: it never crosses the Swift message bridge. An experimental mode can still miss
real-time deadlines; measured queue underflow counters and physical listening are separate
acceptance checks. Linear interpolation is a simple sample-rate converter, not a claim of
hardware-identical reconstruction.

The native host serves only bundled assets plus the selected session's FWSC and initial
flash on a random-token loopback HTTP route, with cross-origin isolation and no-store.
The worker restricts fetches to that origin/session directory, checks the exact generic
module SHA-256 before instantiation, validates package/flash size, boots FM-1 only, and
checks that restored flash is byte-identical. Firmware is not bundled.

`window.FM1Host.command` takes an `id`, an `op`, and operation fields. Every command sends
`{kind:'reply', id, ok, result, error}` through the WebKit `fm1` handler. `load` needs
`packageURL`, optional `flashURL`, `expectedModuleSHA256`, `sampleRate:44100`, and
`guestHz` (one of 120/180/240/320/360 million); it creates a paused engine.
Unsupported clock values are rejected. `play`, `pause`, `flash`, `releaseAll`,
`mute {muted}`, `key {key,down}`, `encoder {encoder,delta}`, `master {value}` and `close`
complete the bridge. Correlation `id` is distinct from matrix `key` and `encoder`.
Playback confirms a running AudioContext before and after prefill, with a bounded startup
failure and stage diagnostics for WebKit activation. Pause disables output, awaits the
producer halt/key release, flushes the PCM generation,
then suspends the context and replies with complete base64 flash plus diagnostics.
For pause/checkpoint snapshots the Worker copies flash into an owned1MiB ArrayBuffer and
transfers that copy; the page host validates its size and performs base64 encoding. WASM
memory is never transferred or detached. This moves encoding off the producer thread;
it does not establish a measured real-time performance improvement. Old
worker events are ignored after replacement, and stale PCM generations cannot play.
LCD snapshots contain base64 RGBA 240×240 pixels only when dirty, with 41 LED values, at
most 10 Hz during production. State values are paused 0, running 1, failed 2.

The private local engine resource is the accepted generic reuse/normal-forward build:
`d3f51e1b50fd90c5be186f592c52a04139faceb5fbefd41c248790e620620c87`.
Its source/build receipt is `Research/HeavyAcceleration/trace-glue-reuse-normalforward-receipt.json`; the resource
copy is excluded from Git. The build preparation step checks this exact pin. This change
does not authorize publication of the binary, firmware, generated source or saved projects.
The generic engine derives from the MIT fm1-emu project pinned in Vendor/UPSTREAM.md;
the application/source-native SLOOP GPL-3.0 notices and attribution remain applicable.

Private functional validation lives at `Research/ModeSwitch12/web-engine.test.mjs`. It
runs the actual generic module against a local phone-backup package/flash, checks exact
flash restoration, control calls, nonzero stereo PCM, LCD/LED shape, generated module
execution, bounded producer capacity and stopping on pause. Its separate worklet probe
checks 44.1→48 kHz interpolation and frame conservation, stale generation rejection,
paused silence and underflow accounting. This is functional Node coverage; actual
WebKit boot, device installation, real-time performance and owner sound acceptance
require their own evidence in docs/verification.md.

WASM render mean/max and rolling128-render p95 are engine-instance counters. They include
core execution/translation/module compilation and PCM copy, while display serialization,
checkpoint encoding, transport and scheduler wait are separate work. Output-counter
elapsed time derives from cumulative requested AudioContext frames divided by the actual
context sample rate. Input, AudioContext and hardware sample rates are distinct.

# Native SLOOP prototype and sequencer regression

The recorded-drum regression is a core throughput problem. A read-only copy of
the owner's SLOOP 2.7.1 diagnostic recorded a 1.068 average render/budget ratio,
1.128 recent p95, and 783,687 missing output frames of 11,854,521 (6.61%).
There were no missing core frames. These counters describe audio shortages,
not an OS deadline trace or a listening judgment.

An offline reconstruction from the copied raw flash retained the 90 BPM drum
pattern. Starting that loop increased the same Mac's steady core cost from about
0.588 to 0.696–0.723 seconds per audio second; stopping it returned to 0.588.
CPU1 retired about 6.6 times as many instructions during the loop. CPU0 still
retired about 234 million guest instructions per second. Guest time/audio time
remained approximately 1.000. The host probe has no Swift UI, audio device or
Dispatch queue, so those layers cannot explain the increased measured core cost.
Sampling still placed most time in interpreter dispatch and block boundaries.
The earlier sustained three-key checks did not cover the saved sequencer loop.

## Architecture

When built with `FM1_NATIVE_SLOOP`, the exact pinned SLOOP 2.7.1 package SHA-256
selects source-native execution. Every unmatched package retains the binary
interpreter and its optional existing static kernels. Selection does not depend
on the package filename or a user-entered version string. The native backend
compiles exact source commit `4ec1ac829fd2bdf2c571ea215fb3d62477d01220`; all
seven generated resource hashes are checked before compilation. A failed native
build fails explicitly. See [build instructions](../Core/native/README.md).

Both backends retain the same serial C ABI. The native engine owns all writable
firmware globals in an aligned per-instance state, using Virtual FM-1's LLVM
state rewrite. Calls bind that instance on their calling thread. No emulation
or native synthesis moves into the audio callback.

Native state retains the complete 1 MiB flash image at physical offsets,
including all four user sample slots. Restore replaces the native state and FIFO;
the first subsequent use initializes firmware settings, projects and sample
indices from those restored bytes. A 32-bit virtual sample-offset range avoids
truncating native 64-bit pointers. NOR programming retains erase/AND semantics.
The host preserves arbitrary audio request sizes through a FIFO around the
firmware's CTL block size. Physical button/encoder IDs and LEDs retain persisted
panel calibration. MASTER follows the firmware's ADC smoothing. Native Q15 audio
uses the same output quantization as `audio.c` plus the original SoC conversion.

`instrument_backend` reports interpretation versus native execution. Optional
`instrument_workload_metrics` counters prove actual active voices, grains,
nonzero output and observed effect configuration during load tests; they do not
claim that every configured effect is individually audible.

## Current validation

The first exact saved-loop native host probe rendered 30 audio seconds in about
0.050 seconds of core CPU time, with nonzero drum audio and a 90 BPM bar cadence
independently checked from the PCM envelope. Its complete final flash remained
byte-identical to its starting input. This is Mac throughput, not iPhone latency.

The initial native Rust workspace run passed 67 tests, including arbitrary host
buffer sizes across CTL boundaries, interleaved independent instances, full raw
flash restore and invalid-length rejection, audible identical samples in each of
USR1–4 with sample-byte preservation, master zero after ADC smoothing, and SHA-256
vectors. The exact upstream DSP suite passed all 182 golden renders unchanged,
with zero health, voice/routing failures or crashes. These source-DSP goldens do
not establish whole-application PCM equality with the binary interpreter.

The source-native main loop is driven every 16 ms of rendered audio, with a
sample-derived clock, instead of interpreting both guest CPUs and hardware IRQs.
Cold boot, input observation and drawing cadence therefore differ. Complete PCM
identity, every preset, editor protocol, arbitrary firmware versions, physical
listening acceptance and long thermal behavior must not be inferred from the
initial probe or the upstream goldens.

## Reproduction and private receipts

`Core/examples/workload_probe.rs` drives the original CPU/peripheral machinery
and records guest/audio clock relationships. `Core/examples/audio_workload.rs`
drives the public ABI with physical key/encoder events at audio-clock timestamps.
Input packages, raw flash, PCM, screens, sampler output and reports remain local
under ignored `Research/SequencerDiagnosis/` and `Research/NativeSloop/`.

The owner subsequently stopped the firmware sequencer and allowed it to save.
A new read-only device copy matched the earlier reconstructed raw-flash hash.
No phone file was reset or overwritten for the diagnosis. Firmware autosave needs
2.5 seconds without input **and** at least 20 seconds since the previous save;
the app's independent five-second checkpoint only copies current flash bytes.
App pause must not be used as a substitute for first letting firmware autosave.

A separate demanding synthetic fixture is generated from fresh firmware-only
flash, never the owner's project. Source limits are eight shared synth voices
across three synth tracks plus six drum voices, 64 steps per track, four notes per
synth step, 16 requested drum lanes, ratchets up to four, and user tempo up to
240 BPM. Requested notes remain subject to the firmware allocator. The fixture
is a demanding legal configuration; it is not a proof of the universally slowest
possible patch or of physical hardware behavior at every extreme.

### Demanding synthetic fixture

The final core adds a sixth native test: physical controls record five drum hits,
close and play the loop, stop, wait through the firmware's initial 20-second save
interval, then restore full raw flash into a new instance. The captured project
bytes match exactly and the restored loop produces audio. The full native
workspace now passes 68 tests; a build with native SLOOP disabled passes 63.

Three separately generated 30-second host probes compared a mixed FM6/PHYS/GRAIN
configuration, all-FM6, and FM6/NOISE/GRAIN. The mixed case was the most expensive
of those three at about 2.25% active render budget on this Mac; the other two were
about 2.0%. This is a bounded comparison, not an exhaustive preset search.
The mixed case actually reached eight shared synth voices (4/2/2), six drum voices
and twelve live grains, with all four tracks active. Its controlled output peak
was 8,997 in PCM16 and it produced 2,204,179 nonzero DSP samples during 25 seconds
of playback. The observed configuration mask includes every instrumented effect
class; it does not prove every effect is independently audible.

The generator accepts only the exact fresh firmware-only flash hash and refuses
to overwrite an existing output or write outside ignored `Research/`. It stores
all four song sections through the source firmware's persistence functions. It
never receives the owner's project. The selected fixture is
`Research/NativeSloop/stress-variant0.flash`; its SHA-256 is
`ff7985162196490ca4d888fc83bc879f075150d7adce5c33684d92cd5650e3b7`.

Private evidence: `Research/NativeSloop/native-tests-final.log`,
`interpreter-only-tests.log`, `golden-tests.log`, `stress-host-v{0,1,2}.txt`;
`Research/Generated/fm1-native-sloop-{simulator,device}.receipt.json` freezes both
platform archives, their native source/resource pins and all implementation hashes.
Final integration and physical-device observations belong in `verification.md`;
these host results must not be substituted for them.

### Post-delivery save retention

Read-only comparison of the confirmed owner backup and the post-delivery phone
copy found 19 differing raw bytes, all in autosave copy A at `0x9F000`. That copy
was stale generation 1 before delivery; the active earlier project was copy B,
generation 2. The new valid copy A is generation 3. Comparing the **active**
projects keeps all four complete track blocks, including every recorded note,
drum step, engine and track parameter, byte-identical. All four user sample
slots, stored song sections, user presets, FM6 banks and settings are unchanged.
The only changed non-checksum project field is global Swing, raw value `0 → 81`;
its origin is unknown and it was retained. Both generations pass header CRC,
payload CRC and the project's own FNV checksum. No phone data was restored or
overwritten for this audit. Private receipt:
`Research/SequencerDiagnosis/retention-native-build5.json`.

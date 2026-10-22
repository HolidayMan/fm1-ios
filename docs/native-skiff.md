# Skiff 1.4 compiled source engine

The optional Skiff backend compiles the pinned original application, synthesizer
and drum engines, audio ISR, main/UI loop, sequencer, pattern bank and full NOR
storage. The native adapter derives its hardware boundary from Skiff's own
`web/emu/felucca_web.c` host. It is not an arbitrary-binary translator.

## Pins and build

- [Skiff source](https://github.com/illuminus5/skiff/tree/v1.4), commit
  `c01fa1ed619266d770ea6552b153612e1b77d0a9`.
- [Released package](https://github.com/illuminus5/skiff/releases/download/v1.4/skiff-1.4.fwsc),
  610,337 bytes; SHA-256
  `0622a752e8304777c042ccea0732ba023e1413baa6dbc8724576e2ec76de02e0`.
- `Core/native/skiff.lock.json` pins the source, package, eight generated resource
  hashes and all upstream licensing/provenance notices.

The release was the primary repository's latest tagged release when checked on
2026-10-22, with its release tag and downloaded package verified live.

Preparation is an explicit developer step and requires build-only Pillow with
RAQM. No package/source download or compilation occurs inside the app.

```sh
Research/NativeFamily/venv/bin/python Core/native/skiff_prepare.py \
  "$PWD/Research/NativeSkiff14/upstream-skiff"
python3 Core/native/skiff_build.py \
  --source "$PWD/Research/NativeSkiff14/upstream-skiff" \
  --out "$PWD/Research/NativeSkiff14/device" \
  --target aarch64-apple-ios --sdk iphoneos
```

`FM1_NATIVE_SKIFF` points the combined Rust build at that prepared source. The
archive is `libfm1_native_skiff.a`; ABI prefix `skf_`, native kind 7, state alignment
16 bytes, audio at 44.1 kHz in 128-frame blocks, and full 1 MiB physical flash.
There is no heap-owned firmware state requiring a destructor. All per-instance
calls remain on the host's serial worker.

The build verifies clean source at the exact commit and every generated resource
before compiling. Build copies remain ignored. Four sample reads, including the
sample waveform display, use checked virtual flash offsets so the original
32-bit serialized sample references remain valid on a 64-bit host. The upstream
host benchmark entry becomes private and unreachable; its process-control calls
are stubbed only in that unused benchmark. The final object has no file/process
API references. The actual firmware's audio, sequencer and save logic are kept.
All other defined symbols are namespaced before the existing attributed LLVM
state rewrite isolates mutable firmware statics.

## Saves and host limits

Each instance retains an independent complete physical NOR image. Original A/B
objects, project formats, rotating pattern bank, CRCs and three sample-slot maps
stay under the original storage implementation. This engine has its own package
identity and saved file; it never opens an unrelated firmware's owner project.

The source host runs the original single-core sound path. Hardware second-core
execution and PLL switching are unavailable; their menu controls cannot create
physical cores or clocks. The adapter also does not expose USB device audio,
USB/editor/update transport or the TRS MIDI jack. Native source execution,
hardware audio parity, physical phone performance and human acceptance remain
separate checks.

## Host regression evidence

The standalone synthetic test is `Core/native/tests/skiff_smoke.c`. It links the
real native archive and uses only new in-memory flash. It passed:

- Boot, original nonblank UI and nonzero note audio.
- Complete 1 MiB flash round trip.
- Original project and pattern save, new-instance reload and byte-exact project
  capture equality.
- Flash isolation and sample-exact audio while alternating two independent
  instances with the same heavy six-track source fixture.
- All three user sample slots sounding through 64-bit-safe offsets, with their
  original sample flash bytes retained.

The rewrite isolated 373 mutable globals in 1,649,968 bytes. Two interleaved
instances each produced 10.002 seconds of heavy fixture audio in 0.150 seconds
combined on this Mac. This is desktop source throughput, not iPhone latency,
output deadline, thermal or listening acceptance. Local receipts and downloaded
packages are ignored under `Research/NativeSkiff14/`.

## Licensing and release boundary

Skiff and the Hugelton Sample Pack are GPL-3.0-only. JIANT-derived DRUM-X retains
GPL-3.0-only; DaisySP/Rings and Fukiai retain MIT; msfa/Dexed synthesis retains
Apache-2.0; fonts retain SIL OFL 1.1; the VSCO-2/VCSL samples retain CC0. Source
changes and full corresponding build/install scripts and notices must be
preserved if distributing a combined build. Full original notices are retained
under `Core/native/licenses/skiff` and bundled in `App/THIRD-PARTY-native-skiff`;
`App/NOTICE-native-skiff` describes this adapter.

BREAK/FUNK contain recordings generated with YuE2. Upstream's exact
`assets/breaks/ATTRIBUTION.txt` records the model, prompts, seeds and processing,
and asserts its individual-creator output permission. The model owner's
[current primary terms](https://github.com/multimodal-art-projection/YuE/blob/main/MODEL_LICENSE)
explicitly permit individual creators to license generated outputs to clients
and say model generation alone does not impose NonCommercial restrictions on
outputs. They separately limit company use of the model weights and disclaim
third-party rights grants. No model weights or model code are in this build.

This private preparation is not independent commercial release or third-party
rights clearance for the generated loops. Preserve that unresolved release
boundary before external publishing; no author has been contacted and no source
or binaries have been published by this task.

## 2026-10-22 regression

The current source passed the complete sample/project/isolation smoke test.
`Core/native/tests/skiff14_song.c` additionally checks the real SONG REST
scheduler, continued playback on another track and project persistence. A
synthetic project emitted by the actual 1.3.2 native library reopens in 1.4
with all 8,140 captured logical bytes unchanged. New REST records cannot be
read by older upstream firmware; old source trees and save files are retained.

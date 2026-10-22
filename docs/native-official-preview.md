# FM1 Open V14 source preview

This optional native backend compiles M-VAVE's public **browser instrument** C
source. The original hardware firmware uses a separate proprietary PI32v2 binary
engine that cannot be linked as an arm64 iOS library from the published SDK. This
backend is identified as **FM1 Open V14 source preview**: hardware DSP, voice
limits, synthesized demo samples, radio, MIDI and audio-device integration can
differ. It does not turn arbitrary `.fwsc` files into compiled native engines.

## Exact provenance

- [Manufacturer announcement](https://forum.m-vave.com/topic/4).
- [Public source](https://github.com/m-vave/fm1_open/tree/4d266850f8a46bd5154a0d495c1f60317156c9f7),
  commit `4d266850f8a46bd5154a0d495c1f60317156c9f7`, V14.
- [Official workbench](https://open.m-vave.com/fm1-workbench). Its V14 preview
  module SHA-256 is
  `14a9a2452e66c18234d8a4de8e3ab6c9702ea01d1ad3ff71e3fb951dd9704dcc`.
- The exact 79-input source fingerprint computed by upstream's `Build-Web.ps1`
  is `e67c048015c91b56702c5a5e4cf007c5cf8df6b1104fa38228ac66d653882ade`;
  the build locks each input hash. This public source uses synthesized demo
  samples. It is not claimed byte-identical to the online workbench module.
- The separately downloadable hardware V14 package is 492,084 bytes, SHA-256
  `7e7b6d260163cdf9d716f7fab44f19be600edeffcd390de74370b83c917fd0c6`.
  Matching that package identifies the requested instrument; it does not imply
  that the source preview executes the package's binary instructions.

The public native build uses unchanged `app/` sources except hardware drivers,
`web/engine`, `web/synth`, and `third_party/synth`. The proprietary
`sdk/lib/libfm1_engine.a` is not linked. Public API headers remain required.

## Local preparation and build

Source and artifacts must stay in Git-ignored directories. Preparation downloads
only on an explicit developer invocation; the app never fetches source or builds
code. An existing checkout is verified and is never reset.

```sh
python3 Core/native/official_preview_prepare.py \
  "$PWD/Research/NativeOfficial14/upstream-fm1-open"
python3 Core/native/official_preview_build.py \
  --source "$PWD/Research/NativeOfficial14/upstream-fm1-open" \
  --out "$PWD/Research/NativeOfficial14/device" \
  --target aarch64-apple-ios --sdk iphoneos
```

The builder requires LLVM 20 `clang` and `llvm-link` together, normally under
`/opt/homebrew/opt/llvm/bin`. Set `FM1_NATIVE_LLVM_BIN` explicitly for another
installation of that version. It uses Xcode's selected SDK, namespaces definitions
before combining archives, rewrites mutable globals before optimization, and
writes an archive/source/compiler/adapter receipt. Pin, toolchain and compiler
failures stop the build with no fallback.

`FM1_NATIVE_OFFICIAL_PREVIEW` points the combined Rust build at the prepared
source directory. Its C ABI uses `ofp_`, 128-frame blocks and 44.1 kHz. Native
state requires 64-byte alignment and calls `ofp_destroy()` before deallocation
to release allocations owned by that instance. Per-instance rewriting derives
from the existing attributed Virtual FM-1 tooling; the original rewriter remains
unchanged. The small wrapper checks its adaptation anchors before execution.

## Saves

The preview owns a separate **536,576-byte logical flash**. A fresh preview starts
with all bytes `0xff`; its original `sim_boot(1)` creates the upstream synthesized
demo sample bank. A nonempty saved preview restarts through `sim_boot(0)`.

This format is independent of the 1 MiB raw binary-emulator flash and all other
firmware projects. Never seed it from hardware-package raw flash, SLOOP saves or
a universal WASM flash branch. Raw-flash compatibility is not claimed.

## Historical local desktop evidence (V13)

Pinned public-source native compilation passed. The state rewrite isolated
246 mutable globals in a 708,224-byte state. The native port and original official
WASM both produced nonzero audio and a nonblank display; an edited project saved
through the original controls reopened byte-identically. Complete logical-flash
restoration and independent-instance state passed. Interleaved native instances
produced identical audio for identical inputs.

The save probe waited for an actual flash revision change; its input sequence
required three SAVE presses in both original WASM and the native port. A fixed
two-press assumption did not establish a save.

On this Mac, eight default tracks covering all six sound-source families,
27 MIDI note-on messages per track and unchanged upstream voice caps produced
10.002 seconds of audio in 0.240 seconds native and 0.392 seconds in Node's
original official WASM. These are desktop source-engine throughput measurements,
not iPhone audio deadlines, latency, thermal behavior, listening acceptance or
hardware-parity results. No simultaneous 27-voice capacity per track is implied.

The exact original WASM has zero imports and 49 exports. Its loader restores
logical projects/samples and boots one compiled instrument. The separate
workbench hardware updater handles the fixed firmware package; the sound engine
has no arbitrary `.fwsc` loader.

Private source, downloaded packages, test fixtures and receipts are in ignored
`Research/NativeOfficial14/`. No binaries or external firmware source are included
in this repository's tracked files.

## Attribution

Project-owned APP and browser sources are GPL-3.0-only with the FM1 SDK linking
exception; no proprietary SDK binary is used here. MIT and Apache-2.0 components
retain their original notices. Bundled notices are
`App/NOTICE-native-official-preview`, `App/LICENSE-native-official-preview` and
`App/THIRD-PARTY-native-official-preview`. Preserve notices and corresponding
source/build/install scripts if distributing a combined build.

## 2026-10-22 release update

Tag V14 and its exact source commit and package were verified against the live
manufacturer repository. The native adapter supplies the absent optional weak
hardware MIDI-panel reset hook as a no-op, matching the browser host behavior.
All-eight native host tests passed (87). A synthetic named project saved by
the actual V13 library reopens in V14 with all 4,064 logical project bytes
unchanged. Its logical flash remains 536,576 bytes; source-native preview
limitations and the separation from raw hardware saves continue to apply.

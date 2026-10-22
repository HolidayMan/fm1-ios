# Additional source-native firmware

The family build compiles the actual Felucca 1.6.1, X0X 1.1.0 and Melodee
1.4.5 application and DSP sources. It preserves the existing exact SLOOP
2.8 backend. The fifth selection is the separately labelled official portable
source preview, described in its own provenance; it does not reproduce the
closed hardware SDK's sound engine.

The community choices used a bounded GitHub-stargazer comparison on 2026-10-18:
Felucca 531, X0X 183, Melodee 116, FoMni 65 and Jangada 31; SLOOP had 546.
This is a public interest proxy, not measured installs or active users. Exact
release commits, package hashes, submodules and every generated resource hash
are in `Core/native/family.lock.json`. Resource generation used the release's
own generators with build-only Pillow 13.0.0 and RAQM. No cached older-version
UI header was substituted. Sources, generated assets and packages stay local
under ignored `Research/`.

The Rust native instance owns an immutable descriptor/function table, aligned
per-instance compiled firmware state, note-transition queue and PCM FIFO.
Felucca and Melodee compile their whole application as one translation unit;
X0X compiles its actual eleven DSP/engine translation units and the host
platform, combines their LLVM IR, then isolates all writable globals together.
The linker/state rewrite covers 313, 156 and 513 writable globals respectively.
The three firmware source trees contain no dynamic allocator calls; dropping
an instance releases its state and Rust buffers. The official preview has its
own tracked allocator teardown and 64-byte alignment.

Felucca, X0X and Melodee keep their original physical 1 MiB NOR layout, A/B
copies and source CRC rules. The official preview has a separate 536,576-byte
logical store. The public C ABI asks the active descriptor for its size;
restore checks the active backend's format before changing the existing
instance. A failed restore retains the prior state. Package selection uses exact
SHA-256 and byte count. Hash-only catalogue classification performs no disk I/O.

All calls remain on the host's serial worker. A sample-derived clock services
firmware main-loop/UI passes; observing a snapshot only copies cached output.
Short piano edges retain the existing bounded queue and release-all semantics.
The source ports replace hardware IRQs, physical flash drivers, update entry,
USB audio and physical second-core execution with the native host platform.
Compiled source, functional compatibility, device performance and physical
sound comparison remain separate claims.

## Historical local evidence (Melodee 1.4.3)

The all-five-native release workspace passed 79 tests. The new cases check
real nonzero PCM and nonblank displays, arbitrary host buffer sizes, exact
package/hash classification, full raw-flash preservation and independent
interleaved instances. One additional test uses the public C ABI for all five:
create, render, snapshot flash, destroy, recreate, reject a wrong length,
restore the exact backend store, compare every byte and render again. This
specifically covers the official preview's shorter store through the same
entry point used by the app.

Private receipts are `Research/NativeFamily/workspace-native-public-abi-final.log`
and `Research/Generated/fm1-five-native-{simulator,device}.receipt.json`.
Those archive receipts include exact source/resource pins and implementation
hashes. They are compilation and host-test evidence, not phone acceptance.

A bounded 30-audio-second desktop workload plays four FM6 tracks in Felucca,
with eight actual simultaneous voices (2/2/2/2): 0.77% measured render budget.
X0X drives both drum kits, both 303 parts and a held break slice: 2.70% measured
render budget. Its conservative activity mask proves the two kits and two 303
parts; it does not establish the held break's audibility. These runs use fresh
source state, never owner projects. They are not exhaustive worst-case searches
or iPhone performance results. A corrected Melodee workload drives sixteen
actual FM6 voices across four tracks (4/4/4/4): 2.19% measured render budget,
2,645,088 nonzero samples and 0.649 unclipped peak. Its tiny native C driver
links the same compiled object used by Rust; it avoids the deliberately
oversized 128-event USB burst that triggered upstream's queue-overflow panic
in the initial benchmark. All three runs prove four active parts, with requests
remaining subject to the original firmware allocators. Details remain in
ignored `Research/NativeFamily/stress-*.json`.

Upstream component licenses and notices are retained in
`Core/native/licenses/`; the app retains `NOTICE-native-family` and the separate
SLOOP/official notices. Earlier research builds included Casio and Sequential factory program
data for which upstream grants no redistribution license; the current INIT
derivation below excludes those data. No source, asset or
binary publication is authorized by these local results.

## 2026-10-22 release update

Melodee is pinned to tag v1.4.5, commit `398ada1e09d864c12f3b778a43e45c7c2a8031b8`. The
separate prepared source root is `Research/NativeFamilyOct22`. Latest stable
GitHub tags and downloaded package hashes for all eight engines were rechecked.
All-eight native host tests passed (87). Actual old 1.4.3 and new 1.4.5 libraries
round-tripped a synthetic edited autosave with all 496 track parameters retained.
This checks the native save content; package-specific host save migration is a
separate app policy. Casio and Sequential factory-program permissions remain open.

## PocketFM INIT soundset

The owner explicitly selected replacement of unlicensed factory programs on
2026-10-22. The derived Melodee 1.4.5 INIT build excludes all 64 Casio CZ-1 and
200 Sequential Prophet factory programs and their packed lookup tables. Each
engine has one clearly named original PocketFM INIT choice; its factory browser
contains no repeated substitute slots. Other licensed Melodee presets remain.

`melodee_init_bank.py` modifies only private build copies of six exact upstream
files. Clean upstream pins, expected derived hashes and excluded upstream header
hashes remain in `family.lock.json`. The compiled resource directory contains
neither factory header; each build also checks the actual compiled object for
all five excluded packed-data arrays and their symbols. The native application
starts new Melodee instances with erased NOR before package decoding. Existing
saves and user-imported native tones retain their original wire structures.

The download's exact hash remains a version selector. Its PI32 program and
embedded factory bank are not used to seed the derived native engine. This
is a distinct soundset, labelled `1.4.5 INIT` in the catalogue and firmware UI.
The public technical INIT encodings are GPL-licensed source; PocketFM supplies
its own envelope settings and names, with no factory-ROM program as input.

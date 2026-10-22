# Source-WASM installation and updates — proposal, 2026-10-22

Status: design, not a shipped loader or an App Review approval. Runtime evidence
is in `source-wasm28.md` and the follow-up WebKit report. The current native
TestFlight application and its saved projects are unchanged.

## Recommended user flow

The instrument picker has Installed and Catalog sections, plus Add from Link.
Catalog cards show firmware, author, version, download size, available features,
and whether this exact version passed our tests. Technical build details live
behind Details. Downloaded versions work offline.

Add from Link accepts a supported GitHub repository/release or an instrument
package. Resolve a branch/tag to an immutable commit before offering installation.
Show the recognized instrument, author and version. Prefer a ready, verified
package; otherwise offer Build for a recognized source adapter. An unknown
repository gets an honest Unsupported project result, not a promise that arbitrary
C or FWSC can be compiled. Source portability and available resources are required.

Show updates as Available, Checking, or Failed. Never replace the running engine
mid-performance. Install side by side; checkpoint the current version and restore
a copy into a disposable candidate. Activate only after validation succeeds.
Retain the previous engine and its original save. Going back opens the previous
version's save, unless reverse migration has independently been proved; do not
claim newer work automatically opens in the older firmware.

Expose project/song/sample/MIDI features from tested capabilities, not the file
extension or a generic promise. Existing SLOOP object export is firmware-specific.

## Where to compile

| Route | Advantages | Costs / limits | Recommendation |
| --- | --- | --- | --- |
| Prepared WASM releases + remote catalog | Fast install, no phone compiler, offline playback, reproducible regression gates | Maintain adapters and a build pipeline | Default |
| Build on demand on a service or author's GitHub Actions | Same in-app URL flow; cache once per source/adapter/toolchain/resources tuple | Service operation, quotas, sandboxing and possibly waiting | Fallback for supported sources |
| Embedded Clang/LLD targeting WASM | Local builds, no source upload, possible offline rebuild with cached inputs | Compiler size, RAM/heat, virtual filesystem, generators and dependency handling; iPhone measurements needed | Separate later experiment |
| Browser/Mac builder exporting an instrument package | No compiler in iOS binary, useful to firmware developers | Extra user step | Good initial advanced option |

Local compilation means C/C++ -> WASM bytecode -> execution by WebKit. It does not
produce a dynamically loaded iOS native library. Browser-hosted Clang/LLD already
exists, establishing feasibility of the mechanism, not compatibility or usable
build cost for SLOOP on an iPhone:

- https://github.com/binji/wasm-clang (original demo)
- https://github.com/cppstudio-io/wasm-clang-runtime (newer implementation; author's claims, not tested here)
- https://github.com/WebAssembly/wasi-sdk (a toolchain targeting WASI, not by itself an iOS-hosted compiler)

Our current source build needs more than Clang: `Core/native/prepare.py` invokes
upstream Python generators (including Pillow-dependent assets), checks seven
generated headers, and supplies the source wrapper and sample-addressing changes.
A local compiler must receive verified generated resources or port these generators.
FM1 Open's proprietary PI32v2 sound library cannot be rebuilt into WASM from its
hardware binary; its portable preview remains a separate compatibility claim.
One stable adapter can serve a family of compatible versions, but a new upstream
hardware API or changed save format can require adapter/runtime work.

## Package and runtime boundary

Define a versioned engine ABI rather than ship the current QA module's export-all
interface. Required operations: initialize, render bounded PCM, key/encoder input,
LCD/LED snapshot, checkpoint/restore, release inputs and shutdown. Optional typed
operations advertise tested sample, project, song and MIDI capabilities. Specify
sample format/rate, ownership, bounds and call ordering. One isolated instance per
instrument; one serial producer owns it. The AudioWorklet consumes bounded PCM
and performs no compilation, synthesis or filesystem work.

The package manifest records instrument ID, immutable upstream commit, release,
adapter/toolchain/resource identities, ABI and minimum host versions, hashes and
lengths, maximum memory, save schema, capability versions, license and attribution.
Our catalog authenticates manifests/packages with a verified publisher signature;
hashes alone do not authenticate an unknown publisher. Third-party imports have a
separate trust label and receive the same runtime validation. Do not execute
arbitrary package-supplied JavaScript or shell build scripts inside the app.

Compile and initialize a candidate outside the active instance; check module
imports/exports, bounded memory, output format and restore behavior. A Worker
timeout terminates an unresponsive candidate; WASM alone does not prevent CPU
denial of service. Keep file/network APIs out of the engine imports. All state
remains in private host storage, namespaced by engine/version/save schema.

Measure startup, first note, UI/control queue delay, render deadlines, actual
buffer shortages, 44.1/48 kHz output, interruptions, thermal and background behavior.
High offline throughput is not a latency or iPhone acceptance result. Existing
research warmup uses a disposable instance and must not modify the user's save.

## Keeping the catalog current

Use upstream releases/tags as discovery and immutable commits as build identities.
For cooperating repositories, authors publish the package through their own
release workflow. For other repositories, our service checks release metadata
periodically with caching/conditional requests; do not assume access to install
webhooks or workflows in somebody else's repository.

Discovery -> exact source/resources -> known adapter -> isolated build ->
boot/control/audio/load tests -> stress deadlines -> migration tests -> publish
versioned artifact -> update catalog. A new release that fails tests remains
unavailable or explicitly experimental; a new tag is not automatic compatibility.
Serve packages as durable release assets, not expiring CI artifacts. Keep catalog
refresh separate from engine downloads; deduplicate builds by content identity.

GitHub supports release and manual workflow triggers:
https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows

No scheduled service, workflow or public distribution was created by this design.

## Apple review boundary

The technical architecture can deliver compatible WASM engine updates without a
new app binary. It does not guarantee that Apple will accept that distribution
model. Guideline 2.5.2 restricts downloaded code changing functionality; 4.7 allows
specified software/plugin categories subject to additional requirements, including
native API exposure (4.7.2) and an index (4.7.4). A user's manual import or local
compiler does not automatically exempt the feature. Present the actual instrument
plugin model, capabilities and download flow to review; do not describe a compiler
as a workaround or silently enable an undocumented loader after approval.

Checked 2026-10-22:
https://developer.apple.com/app-store/review/guidelines/

## Next implementation gate

First validate full SLOOP source-WASM in macOS WebKit with exact output/save
comparison and paced audio. Then test the same source engine in iOS WKWebView on
the minimum physical device, including input latency and interrupted sessions.
After those results, build the versioned package/loader and a small local catalog
prototype. Add a second firmware family before treating the ABI as general.
Investigate embedded compilation only after this simpler user path works.

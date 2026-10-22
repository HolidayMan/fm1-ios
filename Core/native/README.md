# Exact source-native SLOOP backend

The native engine is GPL-3.0 code derived from Virtual FM-1. Exact SLOOP source
and generated resources remain local in ignored `Research/`; they are never
fetched by the application. See `upstream.lock.json` for both pinned repositories
and the seven deterministic resource hashes. `App/LICENSE-native-sloop` and
`App/NOTICE-native-sloop` retain the combined build's license notice.

Use a Python with Pillow for the upstream build-only resource generators:

```sh
python3 Core/native/prepare.py "$PWD/Research/NativeSloop/upstream-sloop-2.8"
FM1_NATIVE_SLOOP="$PWD/Research/NativeSloop/upstream-sloop-2.8" \
  FM1_STATIC_KERNELS="$PWD/Research/Generated/static_kernels.inc" \
  cargo test --workspace --release
python3 Core/tools/build_static_core.py \
  --native-sloop "$PWD/Research/NativeSloop/upstream-sloop-2.8" \
  --kernels "$PWD/Research/Generated/static_kernels.inc" \
  --target aarch64-apple-ios-sim --output Research/Generated/fm1-native-sloop-simulator.a
```

`build.py` requires the exact clean pinned firmware/tools/assets and checks all
seven generated resource hashes before compiling. There is no native build
fallback on a failed pin, resource check, LLVM state rewrite, or compiler call.
The ordinary research Cargo build without `FM1_NATIVE_SLOOP` retains the interpreter.

The copied `sloop_core.c`, `felucca_core*.h`, `fel_state.py` and
`fel_state_build.py` originate from the Virtual FM-1 commit in the lock file.
The C wrapper is adapted for full raw flash, physical controls/LEDs, master ADC
and 64-bit-safe user sample addressing. The LLVM rewrite is unchanged: writable
firmware statics become a separately allocated, aligned per-instance state.

`FM1_FORCE_INTERPRETER=1` explicitly selects the reference binary interpreter in
local comparison tools even when native SLOOP is linked. `instrument_backend`
reports the actual route. Unmatched package hashes always retain interpretation.

## Additional compiled community firmware

`FM1_NATIVE_FAMILY` links the exact released Felucca 1.6.1, X0X 1.1.0 and
Melodee 1.4.5 sources pinned in `family.lock.json`. GitHub stargazers were used
as a bounded popularity proxy when choosing these three; this is not a download
or active-user ranking. Their upstream application, sequencer and DSP sources
compile to native code. They never invoke the pi32v2 interpreter. Per-instance
LLVM state isolation, queued short note transitions, cached display observation
and complete physical 1 MiB NOR storage extend the existing SLOOP route.

Preparation requires build-only Pillow with RAQM and fonttools; X0X also needs
Homebrew LLVM (`clang` and `llvm-link`) to combine its real DSP translation
units before the state rewrite. Runtime has no Python or new Rust dependency.
The exact resource hashes are checked on every build, and a failed pin or
compiler call fails the build explicitly.

```sh
Research/NativeFamily/venv/bin/python Core/native/prepare_family.py "$PWD/Research/NativeFamily"
FM1_NATIVE_SLOOP="$PWD/Research/NativeSloop/upstream-sloop-2.8" \
FM1_NATIVE_FAMILY="$PWD/Research/NativeFamily" \
cargo test --workspace --release
```

Native selection uses exact package SHA-256 and length, never names or version
strings. `instrument_backend` remains 2 for all source-native engines;
`instrument_native_kind` distinguishes 2 SLOOP, 3 Felucca, 4 X0X, 5 Melodee,
and 6 the separately labelled official portable source preview. Catalogue hash
lookup is available without opening a file. Unmatched packages retain the
internal interpreter API for reference tests; the consumer application rejects unmatched packages.

The new wrappers derive from the pinned Virtual FM-1 wrapper commit and X0X's
own host platform. Hardware IRQs, USB audio, firmware updates and a physical
second CPU are not simulated by these source ports. A sample-derived main loop
services firmware UI and saves; snapshot reads do not advance firmware time.
Compiled-source audio is not proof of sample-exact hardware execution or phone
performance. Source and full upstream component notices remain local;
`Core/native/licenses/` preserves the source licenses. The PocketFM Melodee INIT derivation excludes the upstream Casio and Sequential
factory program data; user/imported tones remain supported. See `melodee_init_bank.py`.

Package-level native tests also require the exact release fixtures (not bundled
with the app). Put the three `family.lock.json` package records' verified bytes
at `Research/NativeFamily/<id>-<version>.fwsc`. The public all-five ABI test also
uses SLOOP's pinned `docs/firmware/sloop-2.8.fwsc` and
`Research/NativeOfficial/FM1-Open-V14.fwsc`. Source preparation generates build
resources; it does not silently download or replace these test packages.

## Additional curated source ports

`FM1_NATIVE_EXPANSION` points to an ignored prepared root containing exact FoMni
0.4 and Jangada 1.0.1 checkouts. `expansion_prepare.py` runs their own resource
generators; `expansion_build.py` verifies the source set, generated resources,
notices and release hashes in `expansion.lock.json` before compiling. FoMni's
whole-app portable host and separate DSP translation unit are LLVM-linked before
per-instance isolation. Its in-memory object platform uses unchanged upstream
`storage.c` over complete physical 1 MiB NOR, including original A/B/CRC rules.
Jangada compiles the release's application, DSP, UI and storage in its firmware
unity order, with sample-derived serial main-loop timing. Its 32-bit serialized
sample offsets use a checked virtual range on the 64-bit host.

Kinds are 7 Skiff 1.4 (`FM1_NATIVE_SKIFF`, separate `skiff_build.py`), 8 FoMni
0.4 and 9 Jangada 1.0.1. All three own complete 1 MiB stores and isolated aligned
state. These are exact package/source selections, not name-based aliases. Their
native routes do not execute downloaded firmware instructions. The application
curates supported package hashes; its catalog metadata is separate from these
compiled engines. Source-native timing and hardware execution are separate claims.

Preparation, with the existing build-only Pillow/RAQM environment:

```sh
Research/NativeFamily/venv/bin/python Core/native/expansion_prepare.py "$PWD/Research/NativeExpansion"
python3 Core/native/skiff_prepare.py "$PWD/Research/NativeSkiff/upstream-skiff"
```

Full licenses and component notices are under `licenses/`. FoMni's Chordian data
are CC0 and fonts OFL. Jangada's inherited notice reserves Hugelton sample-pack
rights pending published terms. Compiling these local sources is not a grant to
distribute the samples or evidence of App Store approval. No older UI assets are
substituted for current generated resources.

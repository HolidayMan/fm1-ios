# Additional native source engines

The curated build adds Skiff 1.3.2 (kind 7), FoMni 0.4 (kind 8) and Jangada
1.0.1 (kind 9), alongside the five earlier native choices. Their exact package
hashes identify already compiled engines. Downloaded package instructions are
not executed by these native routes. The app's curated policy remains separate
from the core's internal reference interpreter.

| Engine | Released source commit | Package SHA-256 |
| --- | --- | --- |
| Skiff 1.3.2 | `c4bb2b4e9015cf6244f98db1d319874e15eb0767` | `d77f60a500df772a136358fafba716e8be3d6311dd56430749d5ebb9f476584d` |
| FoMni 0.4 | `6ecd227013cc18def0e89d035b3760eb268b342b` | `71fa8304b91bff89078bfd27e981ed28ca4f0d3c5f406e8fdb5a2ab240fbdbb5` |
| Jangada 1.0.1 | `46e6c2c2ed94b609918aa6f5f7381fac915ffc45` | `c382e334057bd107294940e456e5c1140754917ba152a1958af3aa1696333588` |

Sources are [Skiff](https://github.com/illuminus5/skiff/tree/v1.3.2),
[FoMni](https://github.com/charlesvestal/fm1-fomni/tree/v0.4) and
[Jangada](https://github.com/zednaked/jangada/tree/v1.0.1). The bounded GitHub
interest comparison observed on 2026-10-18 reported FoMni 65 stars and Jangada
31. This is a selection proxy, not measured installations or active users.

Skiff uses its own portable host and original audio ISR/application. FoMni
compiles its exact whole-app portable host and separate DSP unit, LLVM-links
them, then isolates their writable state together. The host's logical object
buffers are adapted to its original physical `storage.c`; the actual released
A/B sector map, CRC validation and object format are retained. Jangada compiles
its actual DSP, sequencer, UI and storage in firmware unity order, with a
sample-derived serial main-loop clock. The original main-loop quiet/gap rules
control saving. Its serialized sample offsets use a checked virtual range on
64-bit hosts, as in the earlier Felucca port.

Each engine owns aligned state and complete physical 1 MiB NOR. The two new
family firmware source trees make no runtime allocations; unused desktop host
file writers are not called. Dropping an instance releases its state. FoMni's
isolated state is 1,431,792 bytes; Jangada's is 1,606,704 bytes. The state rewrite
and exact input/resource checks fail the build on unsupported changes.

## Preparation and verification

Sources, generated assets and test packages remain Git-ignored in `Research/`.
Use the existing build-only Pillow/RAQM environment; no Python package is added
to the app. Preparation runs the release's own font, table and sample tools.
There is no fallback to older generated UI assets.

```sh
Research/NativeFamily/venv/bin/python Core/native/expansion_prepare.py "$PWD/Research/NativeExpansion"
python3 Core/native/skiff_prepare.py "$PWD/Research/NativeSkiff/upstream-skiff"

export FM1_NATIVE_SLOOP="$PWD/Research/NativeSloop/upstream-sloop-2.8"
export FM1_NATIVE_FAMILY="$PWD/Research/NativeFamily"
export FM1_NATIVE_OFFICIAL_PREVIEW="$PWD/Research/NativeOfficial/upstream-fm1-open"
export FM1_NATIVE_EXPANSION="$PWD/Research/NativeExpansion"
export FM1_NATIVE_SKIFF="$PWD/Research/NativeSkiff/upstream-skiff"
cargo test --workspace --release
```

Exact fixture bytes live beside the prepared sources, following their lock
files. Native tests warm Skiff for half a second before input because its
source boot splash suppresses keys. X0X's audible fixture uses a black-key drum
trigger: its white keys edit steps. Isolation comparisons require nonzero
samples, so comparing two silent instances cannot satisfy the proof.

The public C ABI checks exact package classification, actual PCM after boot,
each backend's complete flash size, malformed restore rejection and reopening
all eight stores. A separate public FoMni regression turns all seven physical
encoder IDs and decodes the committed original A/B project, validating header
and payload CRCs. It requires only the intended parameter to change, including
ALGORITHM 1 changing Rhythm and PRESETS 6 changing Transpose. Destroy/reopen
must reload the same working-project checksum. FoMni/Jangada also edit actual
PRESETS 6, wait the original autosave policy and compare logical project
checksums after a fresh instance reload.

## Frozen platform archives

After tests and source freeze, build these serially. The existing private static
kernel inputs remain an explicit local build input for the retained internal
reference core; source-native engines do not invoke those interpreter kernels.

```sh
python3 Core/tools/build_static_core.py \
  --kernels "$PWD/Research/Generated/static_kernels.inc" \
  --native-sloop "$FM1_NATIVE_SLOOP" --native-family "$FM1_NATIVE_FAMILY" \
  --native-official-preview "$FM1_NATIVE_OFFICIAL_PREVIEW" \
  --native-expansion "$FM1_NATIVE_EXPANSION" --native-skiff "$FM1_NATIVE_SKIFF" \
  --target aarch64-apple-ios-sim --output Research/Generated/fm1-eight-native-simulator.a
python3 Core/tools/build_static_core.py \
  --kernels "$PWD/Research/Generated/static_kernels.inc" \
  --native-sloop "$FM1_NATIVE_SLOOP" --native-family "$FM1_NATIVE_FAMILY" \
  --native-official-preview "$FM1_NATIVE_OFFICIAL_PREVIEW" \
  --native-expansion "$FM1_NATIVE_EXPANSION" --native-skiff "$FM1_NATIVE_SKIFF" \
  --target aarch64-apple-ios --output Research/Generated/fm1-eight-native-device.a
```

Each sibling receipt records the archive hash, target, implementation hashes,
source/resource pins and distribution notice hashes. Earlier candidate archives
with an incorrect FoMni encoder inverse map are retained as explicitly rejected
in `Research/NativeExpansion/superseded/`; they are not the accepted build.

Full component licenses remain under `Core/native/licenses/`, with app notices
in `NOTICE-native-family` and `NOTICE-native-skiff`. FoMni's Chordian data are
CC0 and its fonts OFL. Jangada's inherited notice reserves the Hugelton Sample
Pack rights pending published terms. Earlier Melodee's Casio/Sequential factory
program permissions are also unresolved. Local compilation and functional
checks establish neither asset redistribution rights nor App Store approval.
Phone performance and listening remain separate verification steps.

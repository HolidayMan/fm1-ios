# PocketFM native source delivery

This is the source and build route for the native fourteen-engine consumer app.
`SOURCE-MANIFEST.json` in each release-source archive records the actual app
version/build, repository base commit and SHA-256 of every included file. A dirty
base commit is explicitly labelled: the file manifest, not the base commit alone,
identifies that snapshot. Match it to the frozen store archive before publication.
Source availability does not establish App Review approval or legal clearance.

## What recipients receive

The source archive includes the Swift/UIKit app, C audio host, Rust boundary and
vendored MIT Rust crates; all native C adapters, state-isolation tooling, resource
generators/adaptations, locks, licenses/notices; project-generation/build/audit
scripts and source tests. It includes the original generated app icon used by the
app. The generated Xcode project is included and can also be regenerated.

The pinned upstream engine source trees are **separate public downloads**
at immutable commits, recorded below and in `SOURCE-MANIFEST.json`. They are not
duplicated in the application-source archive. Their GPL C source, original
asset inputs/fonts and resource generators are required source inputs, not optional
references. Recipients need network access to acquire these public checkouts.
This is an explicit multiple-download source route, not a standalone offline kit.
If any pinned source becomes unavailable, repair source delivery before relying on
this route for that release; do not silently substitute a different version.

| Engine / source | Exact source commit |
| --- | --- |
| [SLOOP 2.8](https://github.com/isod89/sloop-fm1/tree/b77bf55e3bf804665b8f5dffb5955bd8443311f0) | `b77bf55e3bf804665b8f5dffb5955bd8443311f0` |
| [Felucca 1.6.1](https://github.com/hugelton/Felucca/tree/a53ecf428c29c780108fd70a31b71a32a6b5c313) | `a53ecf428c29c780108fd70a31b71a32a6b5c313` |
| [Felucca-Engines submodule](https://github.com/hugelton/Felucca-Engines/tree/c46e0086f69bdc26df1cd144dca9e683cc4531dd) | `c46e0086f69bdc26df1cd144dca9e683cc4531dd` |
| [X0X 1.1.0](https://github.com/charlesvestal/fm1-x0x/tree/27f6fac7e07ce97b5de158b45aec99f59a9e23fd) | `27f6fac7e07ce97b5de158b45aec99f59a9e23fd` |
| [Melodee 1.4.5](https://github.com/keremimo/melodee/tree/398ada1e09d864c12f3b778a43e45c7c2a8031b8) | `398ada1e09d864c12f3b778a43e45c7c2a8031b8` |
| [FM1 Open V14 public preview](https://github.com/m-vave/fm1_open/tree/4d266850f8a46bd5154a0d495c1f60317156c9f7) | `4d266850f8a46bd5154a0d495c1f60317156c9f7` |
| [Skiff 1.4](https://github.com/illuminus5/skiff/tree/c01fa1ed619266d770ea6552b153612e1b77d0a9) | `c01fa1ed619266d770ea6552b153612e1b77d0a9` |
| [FoMni 0.4](https://github.com/charlesvestal/fm1-fomni/tree/6ecd227013cc18def0e89d035b3760eb268b342b) | `6ecd227013cc18def0e89d035b3760eb268b342b` |
| [Jangada 1.0.1](https://github.com/zednaked/jangada/tree/46e6c2c2ed94b609918aa6f5f7381fac915ffc45) | `46e6c2c2ed94b609918aa6f5f7381fac915ffc45` |

The adapted Virtual FM-1 wrapper/state tooling is included under `Core/native/`;
its origin is [commit c52668953231655046ee142d2b3ab4fd2c8ca0b4](https://github.com/jbschooley/Virtual-FM-1/tree/c52668953231655046ee142d2b3ab4fd2c8ca0b4).
It does not need to be downloaded again to build these adaptations. Vendor's MIT
source/provenance is included under `Vendor/`, with local changes documented.

No ignored local directory, Git history, private project/save, captured audio,
credential, signing certificate/profile, compiled library, executable firmware,
research WASM or proprietary FM1 SDK archive is in the source package. Original
Casio/Sequential `.syx` data and their two generated factory headers are excluded.
Their upstream provenance notices remain as notices, not redistributed banks.

## Build prerequisites

Use macOS with Xcode/Apple SDKs, Git, Rust with the arm64 iOS targets, Python 3.12,
Pillow with RAQM and fonttools, and LLVM 20 `clang` plus matching `llvm-link`.
The inspected toolchain was Xcode 27.1 (27A9275), Rust
`1.97.0-nightly (9eb3be26b 2026-05-18)` and LLVM 20.1.5. The resource lock records
Pillow 13.0.0, FreeType 2.14.3 and RAQM 0.11.0. Exact generated header hashes are
checked, so a different font stack may need adjustment before it reproduces
the same assets. These are build dependencies, not application runtime packages.

Set up a Python environment on PATH, install the recorded Pillow and fonttools
build dependencies, and confirm RAQM is available:

```sh
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install 'Pillow==13.0.0' 'fonttools==4.67.0'
python3 -c 'from PIL import features; assert features.check("raqm")'
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
export FM1_NATIVE_LLVM_BIN=/path/to/llvm-20/bin
```

Pillow wheels may use different FreeType/RAQM versions. When font hashes differ,
build Pillow against the recorded libraries; retain the expected hashes rather
than weakening the verification. Select the installed Xcode with normal developer
tools configuration. No model download, Python runtime, arbitrary firmware or JIT
is part of the consumer application's execution.

## Acquire and regenerate exact sources

Extract the source archive, enter its root and initialize local Git metadata
(`git init`) if it did not come from a clone. The preparation helpers require
Git ignore checks, provided by the included `.gitignore`. No upstream source
checkout is substituted with an unversioned tar directory: the builders verify
each checkout's exact HEAD and unchanged source files.

```sh
git init
python3 Core/native/prepare.py "$PWD/Research/NativeSloop/upstream-sloop-2.8"
python3 Core/native/prepare_family.py "$PWD/Research/NativeFamily"
python3 Core/native/skiff_prepare.py "$PWD/Research/NativeSkiff/upstream-skiff"
python3 Core/native/expansion_prepare.py "$PWD/Research/NativeExpansion"
python3 Core/native/official_preview_prepare.py "$PWD/Research/NativeOfficial/upstream-fm1-open"
python3 Core/native/community/prepare.py "$PWD/Research/NativeCommunityOct27"

export FM1_NATIVE_SLOOP="$PWD/Research/NativeSloop/upstream-sloop-2.8"
export FM1_NATIVE_FAMILY="$PWD/Research/NativeFamily"
export FM1_NATIVE_SKIFF="$PWD/Research/NativeSkiff/upstream-skiff"
export FM1_NATIVE_EXPANSION="$PWD/Research/NativeExpansion"
export FM1_NATIVE_OFFICIAL_PREVIEW="$PWD/Research/NativeOfficial/upstream-fm1-open"
export FM1_NATIVE_COMMUNITY="$PWD/Research/NativeCommunityOct27"
```

The helpers clone only missing upstream checkouts, verify pins and component
notices, and regenerate exact fonts/tables/samples. Felucca initializes its pinned
MIT engine submodule. FM1 Open selects only the public portable source and required
SDK headers; its opaque binary SDK is not linked. Generic upstream clones can
contain files used for the manufacturer's hardware packages; they are not part
of this source archive or the native build's linked source set.

SLOOP's upstream checkout contains the exact release `.fwsc` under
`docs/firmware/`; its existing build validation checks that public package's
identity, although the native engine executes compiled C. This validation input
is obtained from upstream, not redistributed in this source package.

Melodee preparation runs only the seven allowed resource generators. It does not
read the original Casio/Sequential bank inputs or generate
`melodee_cz1.h`/`melodee_prophet_factory.h`. `melodee_init_bank.py` patches six
**build copies** of firmware source and writes `melodee_init_bank.h`; the original
upstream source stays clean. `family.lock.json` records original/derived source
hashes and the INIT soundset. The wrapper starts from erased NOR and does not
copy hardware-package factory data into initial flash. Existing user files are
separate from these source/build inputs.

## Compile the consumer app

```sh
./scripts/build.sh simulator
# Or compile the iOS device target, without signing:
./scripts/build.sh device
```

The Xcode Release phase uses `--no-default-features --features store-native` and
requires all five native source-root variables above. It builds matching Rust/C
archives, excludes research WebKit assets and audits the resulting app. It does
not reuse optional interpreter/static-kernel captures or a prebuilt private
library. Never set `FM1_STATIC_KERNELS` for this source route.

To inspect or modify the app, run `python3 scripts/generate_project.py` and open
`FM1.xcodeproj`. Install on a physical device using your own Apple signing team
and provisioning assets; Apple SDKs, private release keys and App Store signing
credentials are not redistributed. Simulator/device compilation does not claim
bit-identical signing or acceptance. Tests involving firmware fixtures require
their separately acquired pinned public packages; owner projects are never fixtures.

## Prepare and review a release-source archive

From the reviewed application checkout:

```sh
python3 scripts/package_source_release.py \
  --output Research/SourceRelease/PocketFM-1.0-26-source.tar.gz
```

The standard-library-only packager reads an allowlist of source paths, refuses
symlinks and private-key markers, and writes a deterministic tar.gz, `.sha256`
and `.manifest.json`. All outputs must be new files. The archive's file hashes
cover current source contents, including reviewed uncommitted additions. It
never runs native preparation, reads private release configuration or performs
network/upload operations. Its manifest contains public URLs and relative paths.

Before offering this route to binary recipients, compare included source hashes,
all engine pins/resources and the derived Melodee soundset with the exact built
archive's receipt, finish review, and publish the matching source archive plus
this source-download page at stable public URLs. Verify that each upstream pin
remains downloadable. The source package is prepared locally until that public
readback is recorded. No source offer should claim an archive exists at an
unpublished URL or promise a different future revision.

## Community additions — build 29

The six additions and their submodule/source-acquisition pins are documented in
[native-community.md](native-community.md) and in the source manifest. Prepare
them with `Core/native/community/prepare.py` and set `FM1_NATIVE_COMMUNITY` along
with the five existing source variables. Their sources are separate public
downloads at immutable commits; the native adapters, descriptor, component
notices and build tooling are included in this source archive.

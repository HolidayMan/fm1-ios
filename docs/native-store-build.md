# Native App Store artifact boundary

`Release` is the store product. `Debug` is the local research build and defines
`FM1_RESEARCH`. Debug retains WebKit/WASM and the reference interpreter. Release
has no WebKit surface, factory, transaction handlers or clock/execution selectors;
its `Instrument` initializer forces native-only policy even if passed `false`.
Existing experimental saves stay untouched.

Release Xcode builds invoke `scripts/build_core.sh` before Swift compilation,
using `--no-default-features --features store-native` and the isolated
`target/store/` directory. A research archive cannot satisfy its linker path.
The Cargo dependency graph for this feature contains only `fm1-ios-core`; it
compiles the attributed FWSC data decoder directly, without CPU/SoC/ISA crates.
Only exact hashes in the compiled native registry can instantiate an engine.
Package flash initialization remains byte-compatible with the research native
route. `FM1_FORCE_INTERPRETER` cannot change the store policy.

The Release source/resource exclusions remove `WebInstrumentEngine.swift` and
all WebEngine/WASM/JavaScript/HTML assets. The final build phase runs
`scripts/audit_store_artifact.py` against the built app. It checks nested resources,
required privacy declarations, executable symbols and framework dependencies.
The audit reads the exact native policy from the signed read-only Mach-O
`__TEXT,__fm1_policy` section, which survives distribution symbol stripping. A
volatile core check keeps it live through linker dead stripping. The core's
`instrument_research_enabled()` marker is also checked by hosted tests; the Release app refuses to initialize with a research core.
This audit establishes an artifact boundary. Rights, physical device acceptance,
privacy metadata and Apple's signed archive validation remain separate checks.

## Build and archive

Prepare the exact pinned source trees with the existing native preparation tools
before running these commands. No build step fetches missing source or firmware.
For the October 22 source pins, explicitly select:

```sh
export FM1_NATIVE_SLOOP="$PWD/Research/NativeSloop/upstream-sloop-2.8"
export FM1_NATIVE_FAMILY="$PWD/Research/NativeFamilyOct22"
export FM1_NATIVE_SKIFF="$PWD/Research/NativeSkiff14/upstream-skiff"
export FM1_NATIVE_OFFICIAL_PREVIEW="$PWD/Research/NativeOfficial14/upstream-fm1-open"
export FM1_NATIVE_EXPANSION="$PWD/Research/NativeExpansion"
python3 scripts/generate_project.py
xcodebuild -project FM1.xcodeproj -scheme FM1 -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/Store26 \
  -archivePath Research/Store26/FM1.xcarchive \
  DEVELOPMENT_TEAM=YOUR_TEAM archive
python3 scripts/audit_store_artifact.py Research/Store26/FM1.xcarchive/Products/Applications/FM1.app
```

Use the existing authorized signing identity/team. Do not add simulator signing
or testability overrides to the distribution archive. Archive/export/upload and
App Store Connect submission are distinct operations. A native archive passing
this audit has not by itself been submitted or accepted.

For Release simulator tests, add `ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO`
to the usual test command and select an explicit simulator destination. Research
WebEngine tests are compiled only in Debug. Native policy tests run in both.

## Launch and privacy audit

The bundle still contains catalogue metadata rather than external firmware
packages. A fresh offline install displays the panel and a library with disclosed
resource sizes; playing requires an explicit first download. Installed exact
packages and saved projects continue to work offline. Cancellation, unavailable
network and invalid hash/length errors retain existing work. No licensed starter
package is newly bundled by this boundary change.

The manifest declares private app UserDefaults (`CA92.1`) and elapsed app event
timing (`35F9.1`), matching preferences and monotonic input/audio timing in app
sources. No tracking domains or collected-data types are declared. Final App
Privacy answers must account for optional resource requests to upstream hosts;
this manifest does not claim control of their server logs. The app does not read
file timestamps or free disk capacity in the reviewed Swift/C sources. The build
audit verifies these declarations are present; human privacy answers and a
published policy/support URL must be verified separately.

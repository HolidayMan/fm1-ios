# Exact source-native SLOOP backend

The native engine is GPL-3.0 code derived from Virtual FM-1. Exact SLOOP source
and generated resources remain local in ignored `Research/`; they are never
fetched by the application. See `upstream.lock.json` for both pinned repositories
and the seven deterministic resource hashes. `App/LICENSE-native-sloop` and
`App/NOTICE-native-sloop` retain the combined build's license notice.

Use a Python with Pillow for the upstream build-only resource generators:

```sh
python3 Core/native/prepare.py "$PWD/Research/NativeSloop/upstream-sloop-2.7.1"
FM1_NATIVE_SLOOP="$PWD/Research/NativeSloop/upstream-sloop-2.7.1" \
  FM1_STATIC_KERNELS="$PWD/Research/Generated/static_kernels.inc" \
  cargo test --workspace --release
python3 Core/tools/build_static_core.py \
  --native-sloop "$PWD/Research/NativeSloop/upstream-sloop-2.7.1" \
  --kernels "$PWD/Research/Generated/static_kernels.inc" \
  --target aarch64-apple-ios-sim --output Research/Generated/fm1-native-sloop-simulator.a
```

`build.py` requires the exact clean pinned firmware/tools/assets and checks all
seven generated resource hashes before compiling. There is no native build
fallback on a failed pin, resource check, LLVM state rewrite, or compiler call.
The ordinary Cargo build without `FM1_NATIVE_SLOOP` retains the interpreter.

The copied `sloop_core.c`, `felucca_core*.h`, `fel_state.py` and
`fel_state_build.py` originate from the Virtual FM-1 commit in the lock file.
The C wrapper is adapted for full raw flash, physical controls/LEDs, master ADC
and 64-bit-safe user sample addressing. The LLVM rewrite is unchanged: writable
firmware statics become a separately allocated, aligned per-instance state.

`FM1_FORCE_INTERPRETER=1` explicitly selects the reference binary interpreter in
local comparison tools even when native SLOOP is linked. `instrument_backend`
reports the actual route. Unmatched package hashes always retain interpretation.

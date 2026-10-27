# CoralFlower 0.5 native recipe

Exact upstream: <https://github.com/FicusFicusov/CoralFlower>, tag `v0.5`,
commit `b5ceb997be330c8a420958eb8f4e0f4b3ca084c2` (latest release checked
2026-10-27). Package `coralflower-0.5.fwsc`, 610313 bytes, SHA-256
`ab7d0744eed0c83d62be39da9d63c5618e1bccc94de2931a9145a7d4b723b0bb`.
The descriptor pins source inputs, all eight generated headers and notices.
The app selects the signed native engine by this exact package fingerprint;
downloaded instruction bytes are never executed or copied into initial NOR.

`coralflower.c` includes the release's `tools/emu/emu_fw.c` and its exact
`emu_firmware.h` unity order: real FM/VA/drum DSP, audio ISR, chord player,
sequencer, plant renderer, UI, sound banks and original NOR storage code.
Every writable global is moved to instance-owned state through `fel_state.py`
(371 globals; 1,566,928 bytes, 16-byte alignment). The outer host clock follows
the upstream serial headless host: 1 ms input ticks, 15 ms UI frames and audio
ISR blocks of 128 frames at 44100 Hz. Snapshot reads do not advance the clock.
Native ABI output is the upstream portable host's signed Q15 PCM multiplied by
two, because the shared Rust boundary shifts once before float conversion.

The checked `coralflower_adapt.py` modifies only an ignored build copy:

- Serial worker ownership replaces the desktop emulator's recursive CPU lock.
- File-backed NOR becomes the same full 1 MiB instance-owned RAM image; original
  storage layout, CRC/A-B/log rules, page programming, erases and modeled erase
  stalls remain upstream's. Raw saves are restored before initialization.
- macOS `libproc` instruction profiling uses the source's zero-counter host
  fallback on all native targets; iOS has no `libproc` API. Musical sample time
  and the serial second-core synthesis job remain unchanged.
- Desktop `atexit`, environment overrides and physical update/reboot exits are
  disabled. The native owner controls lifetime; no process-wide exit can be
  triggered by a panel gesture.

GPL-3.0-only and component notices are retained in `coralflower-licenses/`.
CoralFlower's author credits ChoralRoot/Felucca, Melodee, MSFA/Dexed and the
Departure Mono/Inter Tight fonts (OFL). The source explicitly selects CZ=0 and
QUAD=0; inherited Casio factory assets are not generated or compiled. The eight
generated headers contain no CZ factory bank. Its generated drum material is
synthetic (`gen_samples.py` reports no imported CC0 sample files). Unused
restricted upstream assets in an ignored source checkout do not grant rights
to redistribute those assets. The cached hardware package includes Apache-2.0
JieLi SDK support files; those are not part of this native compiled engine.

Prepare using the existing build-only Pillow/RAQM Python environment:

```sh
DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib \
  Research/NativeFamily/venv/bin/python Core/native/community/prepare.py \
  "$PWD/Research/NativeCommunityOct27" --kind coralflower
python3 Core/native/community/coralflower_probe.py \
  --source Research/NativeCommunityOct27/coralflower \
  --work Research/NativeCommunityOct27/coralflower-verified
# Optional same-sources ASan/UBSan + original boot-compaction check:
python3 Core/native/community/coralflower_probe.py \
  --source Research/NativeCommunityOct27/coralflower \
  --work Research/NativeCommunityOct27/coralflower-sanitizer-recipe --sanitize
```

The probe verifies inputs, compiles a native per-instance library, compiles the
untouched upstream serial portable C reference to native machine code, and runs
five semantic tests. No web compiler/runtime or WASM binary is involved.
Retained gate: `Research/NativeCommunityOct27/coralflower-verified.log`, five
tests passed (0.295 s). Tests prove boot/LCD, note on/release, physical controls,
independent state/PCM/LCD/NOR, observation timing, semantic settings/preset
reopen, and exact PCM/LCD/NOR equality across 300 scripted 128-frame blocks
against the upstream portable host. Arm64 iOS cross-compilation also passed.

`coralflower_sanitize.c` is a separate test harness, excluded from the product.
Its 900 mixed 1/127/1024-frame iterations exercise two instances, controls,
invalid IDs, volume bounds, snapshots and full raw restores. The native source
was compiled with ASan+UBSan through the state rewrite, and linked with Xcode's
current sanitizer runtime (`detect_leaks=0`, unsupported on this Darwin host).
It passed with no sanitizer diagnostic; peak 29480. Homebrew LLVM 20's older
ASan runtime hung in dyld initialization before `main` on macOS 27; it is not
the runtime used for the successful gate. Logs and synthetic NOR receipts:
`Research/NativeCommunityOct27/coralflower-sanitized-apple.log` and
`coralflower-sanitized/{before,after}.flash`.

Heavy edits leave an original-format settings log. The source's
`cf_settings_load()` compacts it with `st_tidy()` at power-on. Therefore NOR
bytes can change during a normal firmware boot. The sanitizer fixture changed
896 bytes only in settings sectors 0x9D000/0x9E000; replaying that exact preboot
image through the untouched upstream portable host produced the identical
after image, SHA-256
`adc19ca1e7100fd1e7e11d2dcceb8344ed532c17cccb740880673e5715b4f4e0`.
`coralflower-boot-compaction.log` retains the comparison and loaded settings.
The boundary preserves exact raw bytes before boot, and the unit gate checks
semantic octave/preset preservation after boot.

These host checks and cross-compilation are separate from final linked public
ABI tests, simulator user workflows, physical audio acceptance and TestFlight
distribution. The compiled recipe provides no interpreter fallback.

The complete `--sanitize` recipe above was executed successfully after recipe
assembly; `Research/NativeCommunityOct27/coralflower-sanitizer-recipe.log`
retains all five unit passes, the sanitizer probe and the exact boot-image
comparison. Source, resource and commit pin mutations were independently
rejected by the common verifier without modifying the source checkout.

# Skiff licensing

Skiff is free software, licensed under the GNU General Public License, version 3 only
(`GPL-3.0-only`, full text in `LICENSE`). That covers the code and its own assets. A few
bundled or ported parts keep their own licences; they are listed below, and their licence
texts are in `LICENSES/`.

Skiff is a fork of Felucca 1.1.5 by Hügelton Instruments (<https://github.com/hugelton/Felucca>),
under the same licence. Felucca's files keep their copyright notices; Skiff's changes are marked
(Skiff) in the sources.

Copyright (C) 2026 Leo Kuroshita (@kurogedelic), Hügelton Instruments (Felucca)
Copyright (C) 2026 illuminus5 (Skiff's changes and additions)

## What is GPL-3.0-only

Every file in this tree that carries an `SPDX-License-Identifier: GPL-3.0-only` header:

- the firmware: `firmware/` (app, HAL, update loader)
- the build script and tools: `build.sh`, `tools/`
- the web pages (installer, editor, the browser emulator `web/emu/`) and their tests: `web/` (not the Fukiai and DotGothic16 fonts, below)
- the host tests: `tests/`

Three source files are ports and keep the licence of their originals:
`firmware/src/phys_dsp.c` (DaisySP, MIT), `firmware/src/phys_symp.c` (Rings, MIT) and
`firmware/src/fm6_core.c` (msfa, Apache-2.0); two are another project's, unchanged, under its
licence: `firmware/hal/fm1_clk320.h` and `firmware/hal/fm1_clk320_probe.h` (fm1-clk320-probe,
MIT). The firmware built with them is GPL-3.0-only as a whole.

You may use, study, change and share Skiff under the GPL. If you distribute Skiff, or
firmware derived from it, you must also give your recipients its complete corresponding
source under the same licence. That includes devices that ship with modified Skiff inside.

## Hügelton Instruments' own work

All by Hügelton Instruments (Leo Kuroshita), in this tree:

| What | Licence | Where |
| --- | --- | --- |
| Felucca: firmware, tools, web pages, tests | GPL-3.0-only | `LICENSE` |
| The PHASE engine's waveforms: a C port of the oscillator of CrispyZebra (<https://github.com/hugelton/CrispyZebra>) | GPL-3.0 | `firmware/src/eng_phase.c` |
| The DRUM voices and kit | GPL-3.0-only | `firmware/src/drum_voice.c`, `firmware/src/eng_drum.c` |
| The Hügelton Sample Pack: Felucca's drum sounds, made by `tools/gen_waves.py` (not CC0; the SLICE engine's BREAK was built from them through Skiff 1.1, the SLICE test's loop still is) | GPL-3.0-only | `tools/gen_waves.py` |
| The Fukiai icon font (<https://github.com/hugelton/Fukiai>): the firmware's icons (rasterised at build time by `tools/gen_aa_icons.py`) and the web editor's | MIT | `web/fukiai.ttf`, `LICENSES/MIT-Fukiai.txt`, `web/FUKIAI-LICENSE.txt` |

Skiff's changes to Felucca, marked (Skiff) in the sources, and its pictures (`docs/skiff.png` from the firmware's
screen renders, `docs/controls.jpg` and `docs/keystrip.pdf` drawn by `tools/gen_panel_diagram.py`) are GPL-3.0-only
too. So are SLICE's BREAK and FUNK (`assets/breaks/`, after Skiff 1.1): loops cut from drum takes made with the YuE2 music
model by Multimodal Art Projection (<https://github.com/multimodal-art-projection/YuE>), under its permission for
individual creators to publish and distribute what it makes; no YuE2 weights or code are in this tree (how they were
made: `assets/breaks/ATTRIBUTION.txt`).

## Third-party material

| What | Licence | Where |
| --- | --- | --- |
| Barlow Condensed font (Medium, Bold) by The Barlow Project Authors (<https://github.com/jpt/barlow>): Skiff's UI text, rasterised into the firmware at build time (`tools/gen_aa_font.py --preset barlow-condensed`; the generated tables are not offered as a font, and the font declares no Reserved Font Name); (Skiff 1.0) also the web editor's headings, labels and values, served with it from `web/fonts/` (its OFL text beside it) | SIL OFL 1.1 | `assets/fonts/BarlowCondensed-Medium.ttf`, `assets/fonts/BarlowCondensed-Bold.ttf`, `web/fonts/`, `LICENSES/OFL-BarlowCondensed.txt` |
| Inter Tight font by The Inter Project Authors: Felucca's UI text (the `inter-tight` preset, kept in the tree) | SIL OFL 1.1 | `assets/fonts/InterTight[wght].ttf`, `LICENSES/OFL-InterTight.txt` (also `assets/fonts/OFL.txt`) |
| Instrument samples (Versilian Studios VSCO-2 Community Edition, VCSL): the SAMPLE sets, also the SLICE engine's PIANO (the PIANO set's middle C) | CC0 1.0 | `assets/samples-cc0/`, provenance in `ATTRIBUTION.txt` there |
| DaisySP by Electrosmith, Corp and Emilie Gillet (<https://github.com/electro-smith/DaisySP>): the PHYS engine's modal and string models and the resonator, ported to fixed point | MIT | `firmware/src/phys_dsp.c`, `LICENSES/MIT-DaisySP.txt` |
| Rings by Emilie Gillet (<https://github.com/pichenettes/eurorack>): the PHYS engine's sympathetic strings, ported to fixed point | MIT | `firmware/src/phys_symp.c`, `LICENSES/MIT-Rings.txt` |
| msfa by Google Inc. and Pascal Gauthier, from Dexed (<https://github.com/asb2m10/dexed>): the FM6 engine's synthesis, ported to integer C (Dexed itself is GPL-3.0; only msfa is used; the FM6 factory patches are Felucca's own) | Apache-2.0 | `firmware/src/fm6_core.c`, `LICENSES/Apache-2.0-msfa.txt` |
| JIANT FM by juanjiant-bit (<https://github.com/juanjiant-bit/JIANT>), a Felucca fork: the DRUM-X engine (its voice and factory kit as written; its engine wrapper, kit pages and test adapted to Skiff, modified 2026-10-10). DRUM-X follows the idea of Sonic Charge's Microtonic; no Microtonic code is involved | GPL-3.0-only | `firmware/src/drumx_voice.c`, `firmware/src/eng_drumx.c`, `firmware/src/ui_dx.c`, `tests/drumx_test.c` |
| klattsch by Tony Gies (<https://github.com/tgies/klattsch>): design reference for the VOICE engine; no code copied. Formant data from Klatt (1980) / Hillenbrand et al. (1995) | MIT (klattsch) | credit only |
| X0X by charlesvestal (<https://github.com/charlesvestal/fm1-x0x>), a Felucca fork: the design of the browser emulator (the worklet, the device clock driven by its audio, the exports); its files credit it in their headers | GPL-3.0 | `web/emu/` |
| The second core (Skiff 1.3), as Felucca 1.6.1 has it (<https://github.com/hugelton/Felucca>, commit a53ecf4, by Leo Kuroshita and gospodindilly-ops): its start, mailbox and hold from X0X by charlesvestal (`hal/fm1_cpu1.h`, `hal/fm1_cpu1.S`, unchanged), after Melodee by Kerem Kilic (<https://github.com/keremimo/melodee>) and with Jangada's measurements and hardening by zednaked (<https://github.com/zednaked/jangada>); the render split and its host tests adapted to Skiff's six tracks | GPL-3.0-only (X0X, Melodee, Jangada: GPL-3.0) | `firmware/hal/fm1_cpu1.h`, `firmware/hal/fm1_cpu1.S`, `firmware/src/fx.c`, `tests/c1_host.h`, `tests/dualcore_test.c` |
| THEME CUSTOM (Skiff #27) after Felucca 1.6's CUSTOM palette by Leo Kuroshita (<https://github.com/hugelton/Felucca>, commit 1727537: `editor_palette.c`, the editor's palette card): its show / store / remove / drop ops, the live preview and the readability warning; widened to the six tracks' colours and a look, one command (39) with the colours in pack7, written for Skiff | GPL-3.0-only | `firmware/src/editor_preferences.c`, `firmware/src/ui.c`, `web/editor.html` |
| DotGothic16 font by The DotGothic16 Project Authors (<https://github.com/fontworks-fonts/DotGothic16>): the browser emulator's knob labels, served with its page (cut to printable ASCII; the font declares no Reserved Font Name) | SIL OFL 1.1 | `web/emu/fonts/DotGothic16-subset.woff`, `LICENSES/OFL-DotGothic16.txt` (also `web/emu/fonts/OFL.txt`) |
| fm1-clk320-probe by curist (<https://github.com/curist/fm1-clk320-probe>): the switch from the FM-1's 360 MHz to JieLi's rated 320 MHz behind MENU > SYSTEM > CPU CLOCK (the check of the clock registers, the switch, its reason codes and a crystal-timed clock loop), unchanged; its sequence after the JieLi AC79 SDK's `sys_clock_update` (Apache-2.0) | MIT | `firmware/hal/fm1_clk320.h`, `firmware/hal/fm1_clk320_probe.h`, `LICENSES/MIT-fm1-clk320.txt` |
| The SMK-37 board layer by genkigenki (M. Geisler) for Felucca (<https://github.com/genkigenki/Felucca>, branch `smk37`, commit b67312c; hugelton/Felucca#237): the M-VAVE SMK-37 Pro build target behind `BOARD_SMK37` (the input HAL, its velocity and pads, the LCD pins and the pad LEDs, the SMK flash map and its guards, the store's owner tag and the stock mapping's marker, the update staging and loader windows, the per-model identities, the package's region table, the installers' model rule and their tests), adapted to Skiff (its detent decoder on the SMK knobs, its store and pattern pool, its LED picture), modified 2026-10-18 | GPL-3.0-only | `firmware/hal/smk_input.h`, `firmware/hal/smk_compat.h`, `firmware/hal/fm1_flash_map.h`, `firmware/hal/fm1_lcd_hw.h`, `BOARD_SMK37` blocks in `firmware/`, `tools/build.py`, `tools/fm1pkg_make.py`, `tools/fm1_install.py`, `web/fm1ota.js`, `web/fm1pkg.js`, `tests/smk_*`, `tests/ldr_test.c`, `tests/ota_test.c`, `tests/install_test.py`, `web/test_web.mjs` |
| fm1-to-smk37 by genkigenki (<https://github.com/genkigenki/fm1-to-smk37>): the SMK-37 hardware notes (pins, matrix, flash map, update) the SMK-37 build was checked against; no text of it is in this tree | CC BY-NC 4.0 | credit only |
| JieLi AC79 SDK by JieLi Technology: three of its files go into every `.fwsc` package (below); none are in this tree | Apache-2.0 | `LICENSES/Apache-2.0.txt` |

On the device, HOME held > ABOUT opens the information screen; turning PRESETS scrolls on into
CREDITS, a short list of these authors, licences and source URLs.

## JieLi SDK files in the packages (Apache-2.0)

A `.fwsc` package made by `tools/build.py` (with `tools/fm1pkg_make.py`; this is the package the
web installer installs) holds three unmodified files from the JieLi AC79 SDK
(<https://gitee.com/Jieli-Tech/fw-AC79_AIoT_SDK>, `cpu/wl82/tools/`). They are read from your SDK
checkout at build time (see BUILDING.md); no SDK files are in this tree.

| File in the package | What it is |
| --- | --- |
| `uboot.boot` | the first-stage boot loader (SPL) |
| `cfg_tool.bin` | the chip configuration block |
| `eq_cfg_hw.bin` | the default hardware EQ table |

They are licensed under the Apache License, Version 2.0 (`LICENSES/Apache-2.0.txt`), not under
the GPL, and their copyright stays with JieLi Technology. The SDK has no NOTICE file. Apache-2.0
files may be distributed together with GPL-3.0 code; Skiff itself stays GPL-3.0-only.

Every distribution of a package carries the licence texts with it: the release folder
(`tools/build.py --release`) and the site (`web/make_site.py`, next to the package in
`firmware/` and linked from the installer page).

## No vendor material

No M-VAVE material is part of Skiff. The firmware links no vendor code and contains no vendor
data, and the packages hold only Skiff and the three SDK files above. The installer's
"Return to official V15" holds only the official file's size and SHA-256: you select the
official firmware file you downloaded yourself, and it is checked and installed in your browser,
never uploaded or redistributed.

## Contributions

Contributions are welcome under GPL-3.0-only.

## Trademarks

"Felucca" and "Hügelton Instruments" are names of Hügelton Instruments. Skiff is not Felucca,
and is not made, endorsed or supported by Hügelton Instruments.

"M-VAVE" and "FM-1" are trademarks of their respective owners. Skiff is independent
firmware that runs on FM-1 hardware. It is not affiliated with, endorsed by or supported
by those owners.

## Radio

Skiff never enables the Bluetooth / Wi-Fi radio of the hardware.

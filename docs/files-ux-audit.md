# Files workflow audit — 2026-10-20

The SLOOP save function is real. It serializes typed musical objects and sound
dependencies, recreates a separate native instance, validates it, writes recovery
before replacement, and commits the restored data. It is not a CPU snapshot or a
hardware-compatible project-file format. Support is pinned to SLOOP 2.8.

## User-facing changes

- Three task-oriented tabs: Saved work, Samples, Audio. Shorter spacing, no
  extra glass wrapper around the native segmented picker, no oversized empty card.
- Named musical copies have their own library. Recovery files and complete SLOOP
  backups live in one collapsed group, instead of competing with user work or
  appearing as repeated actions on every tab.
- Explain that copies are immutable snapshots of the working loop, A–D sections,
  arrangement and shared banks/USR samples. They do not remember held notes or
  transport position. Opening replaces current musical work and shared sounds,
  while retaining global settings. Local opening now confirms this just as an
  imported file already did; cancellation leaves work untouched.
- Backup descriptions identify the SLOOP workspace and settings, and explicitly
  exclude other instruments, saved-copy library and app preferences.
- Sample guidance describes one shared slot, approximately 7.38 seconds, mono
  22.05 kHz, and how to select it in SAMPLE/SET or GRAIN/SRC. The former claim
  that every saved project changes was wrong: named copies embed their samples.
  Current tracks/sections change, saved copies do not.
- Audio describes a fresh render, not live capture. It follows the saved loop/song
  mode, runs for a chosen duration, and adds an explicit tail. The total duration
  is shown. MIDI/live recording/stems are limitations in expandable help, not
  prominent nonfunctional feature sections.
- Import review is kind-specific: musical overlay versus full SLOOP replacement.
  Saved copies are not advertised as interchangeable with hardware project files.

## Remaining limitations

These changes do not implement MIDI, live recording, stems, bar-count exports,
other-engine file formats, hardware transfer, sample-slot audition before
replacement, or library rename/delete. Export destination confirmation belongs
only to the actual system file-provider completion, not to file preparation.
A complete SLOOP backup is larger and more personal than a musical copy because
it includes instrument settings and storage. SONG playback/SONG REC must be
stopped before capture; ordinary loop playback can continue.

## Validation

Targeted real native-engine format/transaction/sample/WAV tests and a simulator
save/open/export flow are recorded in Research/FilesUX24. Visual captures come
from the native app, not a design mockup. Current changes are a local UI revision;
TestFlight 0.6.6 (23) remains the previously delivered panel-layout build.

Final results: 17 file/transaction/sample/audio unit tests passed; the final iPhone 12 UI flow passed save, cancellation, confirmed reopen with recovery, named export preparation, duration/tail selection, WAV preparation and return to Playing. The first UI attempt exposed the missing Cancel control in a landscape popover; an explicit alert fixes that path. Final capture review also identified unlabeled duration pickers; permanent labels now sit above side-by-side controls, stacking at accessibility text sizes. External Files/Share delivery and physical phone acceptance were not exercised.

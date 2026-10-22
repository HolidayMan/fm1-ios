# File workflow fixes — build 27 candidate

This change addresses native startup and SLOOP file actions. The physical report
was on 0.6.8 (25): after a warm-session failure, every firmware could remain at
“choose firmware” until restart. The exact original trigger has not been
reproduced on the phone. These fixes address independently reproduced failure
paths; simulator acceptance is not physical-device acceptance.

## Changes

- Publish the first native LCD frame even without audio callback progress.
- Detect stalled audio startup, retry the graph once, and report a recoverable
  error if it still fails. Firmware selection no longer silently dismisses when
  an operation prevents loading.
- Suspend the synth while auditioning a sample and retain manual pause intent.
  Audition activates playback audio explicitly and reports playback failures.
- Decode WAV, AIFF, M4A and MP3. One waveform combines trim handles and playhead;
  a full-recording overview allows choosing material beyond the initial region.
  Preview matches the encoded, optionally normalized sound.
- Import into any USR slot and optionally assign synth Track 1–3 atomically.
  Preserve the rest of the current workspace and save a recovery backup first.
- Delete workspace backups with confirmation and durable Undo. Projects and
  autosaves are unaffected; Undo refuses destination collisions.

## Evidence boundaries

Native host tests cover the typed project/backup format, corrupt-input
nonmutation, all twelve track/slot assignments, selected-track persistence and
sound after reloading. Platform tests cover actual audio preview, lifecycle
policy, bounded graph recovery, project replacement and backup deletion.

A private read-only copy of the owner's installed workspace was tested only on
further copies. Its current 2.8 startup/reload and supported 2.7.1 migration both
passed; the preserved 58-file source copy remained byte-identical. No physical
save was reset or replaced.

The initial full platform run executed 112 cases: 104 passed, seven explicitly
opt-in performance/stress cases were skipped, and one new test failed because
Foundation cached URL metadata after a file was replaced by a symlink. A small
Foundation reproduction verified the cached-value behavior; the test now checks
readlink and fresh metadata. The product's collision guard already retained both
files. The corrected deletion group passed all 11 cases. Combined unique coverage is
105 passing platform tests and seven explicit opt-in skips. The Rust workspace
passed 88 tests, and Python checks passed 25 tests.

Private receipts and document-provider screenshots are under
`Research/FilesQA27/`; they are excluded from source publication. System Files
export/import and visual acceptance are tracked separately from host tests.

## Deliberate limits

This is a single-zone sample importer. Automatic chopping, multi-file drum kits,
MIDI file import/export, and official web-editor JSON/`.sloopsong` interchange
are not implemented. PocketFM projects/backups use the app's own checked format.

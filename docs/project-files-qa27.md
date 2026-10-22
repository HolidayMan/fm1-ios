# File workflow fixes — builds 27–28

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

## Simulator UI acceptance

Independent screenshot review confirmed a single waveform with two trim handles
and the active preview control. Completed system-UI scenarios cover named-copy
save/open cancellation and confirmation, WAV preparation, backup restore, delete
cancellation/confirmation and Undo, and sample audition while manually paused.
The full sample scenario selects a region beyond 60 seconds in a 120-second real
Files import, zooms and trims a handle, plays/stops preview, assigns Track 3 and
returns to the playing instrument. All use isolated synthetic workspaces.

Earlier UI failures were retained as harness receipts: the native Files title
changes accessibility role; duplicate backup names require a count assertion;
scrolling the parent sheet or pulling down at the top interacts with the wrong
view or dismisses the editor. These were corrected in tests without production
changes. External Files delivery/reimport is recorded separately.

## Final external-delivery finding

The real Save to Files → external backup picker → import confirmation path
wrote both the imported named backup and its recovery copy (library count +2).
A production UI defect nevertheless kept showing the earlier “Saved” delivery
receipt, masking the new import result. Build 28 clears that receipt on a new
nonempty store status or store error, while cancelled pickers and nil resets
retain the preceding result. This also covers subsequent copy, sample, restore
and backup-library actions. Independent review found no blocker in this fix.
Build 27 was uploaded but was not assigned to Owner Beta.

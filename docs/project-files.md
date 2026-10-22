# Projects and files: first SLOOP workflow

The file workflow currently supports the exact compiled SLOOP 2.8 package.
Other compiled instruments retain their existing automatic local saves; the file
window does not advertise unsupported project, sample, MIDI or offline export actions.

A version-1 `.fm1project` carries the live working object (including unsaved edits),
sections A–D, song arrangement and its shared sound dependencies: user preset
banks, FM6 bank, SYN drum kits and all four full USR sample slots. Opening it
overlays these components on the current workspace. Global settings, learned
MIDI map, theme, physical master level and unrelated raw storage are retained.
Shared banks and sample slots can affect other pieces and are disclosed in the UI.
Projects exported through the file service replace the unused raw storage baseline
with erased bytes and omit settings, MIDI and theme content. This prevents an old
raw A/B generation or unrelated private settings from leaking through Share.

A `.fm1backup` includes a complete 1 MiB storage baseline plus twelve typed live
objects, arrangement and four sample slots, with the physical master setting.
It restores the matching SLOOP workspace; it does not include other instruments,
the project library or the app preferences. Both formats have version and exact
package identity checks and SHA-256 checks for every component. Their extension
must agree with their declared kind. Bounds and the firmware's own object CRCs
and validators are checked before a candidate can replace the current engine.

Saving is a musical snapshot, not process-memory serialization. Held notes,
transport position, queued scene transitions and a SONG REC pass in progress are
not restored. Stop SONG playback and finish SONG REC before capture: during SONG
playback the source parks the underlying working loop separately. The bridge
rejects that state rather than exporting the temporary active scene as the loop.
Ordinary loop playback can be captured without waiting for the idle autosave.

## Transaction and recovery

The picker first copies and validates a file into owned staging and presents a
review. It does not open or replace anything. Confirmation creates a named local
copy before application. The serial engine worker constructs and validates a
separate native candidate. Immediately before replacement it captures the latest
current workspace and writes a complete recovery backup atomically. Only then
does it replace the live instance and automatic save. A validation, disk or audio
start failure retains the old instance; a failure after installation restores its
automatic-save bytes. The old instance is destroyed only after successful commit.
Staging cleanup is restricted to the store's own staging directory.

The typed working object is committed using the upstream A/B storage and CRC rules,
so reopening immediately does not wait for the ordinary 20-second autosave gap.
Empty MIDI objects explicitly restore the upstream default map, rather than
inheriting an older map from the baseline. Candidate typed writes clear queued
PCM and physical input transitions. Engine calls stay on their serial worker;
the audio callback continues to read only the existing sample ring.

## Samples and audio

Sample import replaces one zero-based bridge slot, shown as USR1–USR4. The Swift
converter decodes and trims WAV, creates mono 22.05 kHz IMA ADPCM and a complete
81,920-byte FSMP slot. The bridge validates header, zones and data CRC before any
slot write, and reads back every byte. Applying a sample uses the latest current
workspace, changes only that slot and saves a full pre-replacement recovery copy.
The payload is at most 81,408 bytes (about 7.38 seconds at 22.05 kHz).
To play an imported instrument on the panel, select the SAMPLE engine on a synth
track and choose SET = USR1–USR4; GRAIN also offers these slots as SRC. This first
importer creates one instrument zone, not the upstream multi-file drum-kit builder.

Offline WAV export receives a fresh complete working snapshot and package bytes,
then owns an independent native instance on its own serial queue. It renders a
new take for the selected duration and an explicit effects tail. It does not
advance the live engine. This is not a live performance recording or additive
stem export. No MIDI file import/export is implemented by this slice.

## Verification boundaries

`Core/src/project_io.rs` tests public typed operations, unsaved loop and RAM-only
section capture, immediate full-save reopening, all four sample slots and bad-CRC
nonmutation, default MIDI restoration over old nondefault flash, and rejecting a
parked working loop during SONG playback. `FM1Tests/ProjectFileFormatTests.swift`
covers checksums, identity, scope overlays, share scrubbing, type-label mismatch,
and staging without opening. Platform archives must be rebuilt after Core changes.
Simulator UI/system document-provider acceptance is recorded separately from
source checks and native host tests. No owner save or phone action is needed to
run these tests.

The library is a `Projects` child of its exact instrument workspace, including
isolated test fixtures. It never falls back to a shared sibling library. Import
staging is under that library; user exports use separate temporary directories
with readable names before Save to Files or Share.

## Explicit song export — 0.6.7 (24)

The folder entry is capability-gated to the exact native SLOOP backend. Other
engines retain autosaves but do not show this file window. Named copies and
backups already include arrangement and sections; this release adds an explicit
Loop / Whole song audio choice. Loop forces loop mode on the disposable render
instance and uses the selected duration. Whole song forces song mode and disables
repeat only on that copy, checks every referenced section, then follows the
firmware's running arrangement clock until completion. A selected effects tail
is appended. Host polling rounds completion by less than 3 ms (128 source
frames); it does not infer duration from a single BPM. There is a 30-minute
safety limit and cancellation cleanup. Unsupported or missing-section songs
produce an error, never a completed partial file. Live mode and repeat flags
are not changed by preparing either audio export.

## SLOOP 2.8 native update — 0.6.8 (25)

SLOOP is now compiled from official tag v2.8, commit
`b77bf55e3bf804665b8f5dffb5955bd8443311f0`, and selected only for the
verified `fb69b4311790eb7ec09498be16ae2b71bd681840e221c0d8cfdb26fb5f9a2928`
package. The new persisted FX FADE setting is restored by the host adapter.

Exact 2.7.1 project/backup envelopes remain readable under 2.8. Musical project
overlays adopt the current engine identity and preserve current settings. When
2.8 has no autosave, the loader copies bytes from a verified 2.7.1 predecessor,
preferably the remembered workspace, and restores them into a disposable
candidate before writing a separate 2.8 autosave. Original packages, autosaves,
and named files remain unchanged. Ambiguous predecessors and damaged sizes fail
explicitly. Other firmware hashes are not accepted as compatible.

Host release workspace: 87 passed. Actual old/new C-engine probes retain all 12
logical objects, A–D, settings and four sample regions; old fixture is untouched.
Upstream 2.8 UI suite includes new NOTES/drum editing and 20,000-frame fuzz.
Simulator validation and TestFlight distribution receipt:
`Research/Sloop25/verification.json`. Physical phone acceptance is separate.

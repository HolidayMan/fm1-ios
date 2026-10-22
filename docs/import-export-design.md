# Projects, samples and export — design proposal

Status: initial design, followed by a first SLOOP implementation on 2026-10-19.
The native screen, projects/backups, WAV sample import and separate-instance WAV
rendering are implemented; MIDI transport, live recording and the other engines'
typed interchange remain future work. See [implemented scope](project-files.md)
and [verification](verification.md). This proposal targets the eight pinned native
engines in 0.5.0; capabilities must follow the engine **and version**, not the
physical enclosure. The interactive proposal uses illustrative project/audio
content, not the owner's saved music.

## Entry and navigation

One labelled folder action, **Projects and files**, in the app's upper toolbar.
It remains available when the header is collapsed without covering playing keys.
It opens a native sheet, never a second emulated device screen. Three sections:
**Projects · Samples · Export**. Firmware selection stays in its existing place.
External MIDI connections belong in Settings, separate from exporting a MIDI file.

Landscape: list or settings on the left, waveform/details on the right. Compact
widths: one vertical flow. System typography, Dynamic Type, VoiceOver labels,
44-point touch targets, clear Done/Back, no drag-only required interaction.
Keep normal playback running while browsing. File conversion and list work must
not invalidate the synth panel or run on the main/audio thread.

## Projects: keep the work safe without asking repeatedly

The first row is **Current work**, with firmware/version, project name and a
saved/modified status. **Save a copy…** creates a named library item containing
the actual working project, including edits not yet saved into firmware slots.
Autosave continues independently; manually named copies are not overwritten.

Three different things must stay explicit:

| User item | Contents | Purpose |
| --- | --- | --- |
| Project | Working sequence, project settings and required timbre/patch-bank/sample dependencies where supported | Continue this piece of music |
| Firmware format | Original editor/device project, timbre or sample-bank file | Interchange with the matching firmware/editor |
| Full backup | Engine/version, all persistent slots, settings and sample memory; working state too if the adapter can capture it | Restore this engine's workspace |

The mockup's `.fm1project` and `.fm1backup` names are proposed app-container
extensions, not existing hardware/editor formats. Final schemas, registered content
types and extensions are decided during implementation; preserve original formats
for device/editor interchange instead of renaming their bytes.

Do not label an existing flash snapshot as “current project”: the snapshot can
omit unsaved edits. If a complete working-state capture is unavailable, say what
the backup includes. Firmware-slot management is an advanced subpage, not the
default save experience.

**Import:** system Files picker → inspect → preview name, source firmware/version,
required samples and compatibility → **Open as a copy**. Before switching, capture
the current work; if capture fails, stop the switch and keep it open. Unsupported
files get an explanation and retain the existing project. No silent reinterpretation
of another firmware's memory or automatic firmware changes.

Dependency inspection includes patch banks, not just audio: SLOOP FM6 projects can
reference a patch slot rather than contain the edited patch. A self-contained app
project must capture the required bank content or clearly report missing patches;
copying only the original firmware project file cannot guarantee the same sound.

**Restore backup:** separate action with scope preview, automatic pre-restore
backup, explicit confirmation, validation and atomic commit. Imports never erase
the existing library. Cancel leaves current work intact.

## Samples: listen, trim, choose a slot

Flow: **Add sound → Files → preview/trim → destination → Apply**. Start with WAV
input; other decoder-supported formats may follow after actual tests. No firmware
flashing or cloud conversion is involved. A later **Record microphone** action is
separate and requests permission only when used.

Preview shows source name, waveform, selected duration and converted capacity.
Audition only the selected region. Use large draggable trim handles plus editable
start/end times and small step controls; users need not make a precise gesture.
Zero-crossing adjustment is optional and must not move a transient silently.
Normalization defaults off; show clipping and offer a deliberate gain adjustment.
Conversion to the firmware's sample rate/channel count/codec is explained in the
destination summary. Preserve the original audio separately until the user deletes it.
Firmware-specific advanced import can expose zones, root notes, loops or slices
only when its format supports them. Retain existing slice/zone metadata on a
round-trip; surface Skiff's reduced capacity when persistent manual slices are used.
Do not duplicate the firmware's normal sound-editing controls in this file workflow.

Show the actual slot count and names, capacity after encoding, existing content,
and shared-bank scope. Disable Apply while the result does not fit; offer trimming,
not an unexplained failure. Never quote one universal duration across engines.

For an occupied slot: **Replace “Snare” in USR2?** Explain whether all projects
using that shared slot will change, save the previous bank, and offer Cancel or
Replace. Perform decode/encode off the engine worker; apply the validated result
at an adapter-defined safe boundary. If stopping transport is required, tell the
user before Apply and restore the previous playback state after success/cancel.
Read back and verify the committed payload. A recoverable old bank must survive
a failed write or interrupted import.

## Export: choose the musical result, then the destination

**Audio (WAV)** is the default: it preserves the sound, samples and effects.
Choose **Record performance** for actual live playing, or **Render project** for
a fixed scene/song range when that adapter supports a reproducible snapshot.

- Recording has a visible elapsed timer, input/output meter, Stop and a recoverable
  partial file. Capture internal synth audio without a microphone permission prompt.
- Rendering offers a scene/song range, repeat count and an explicit effect-tail
  duration. Use the engine's real sample rate; show WAV bit depth and channels.
- Capture the current mix, including firmware MASTER; the phone's listening volume
  must not change the file. Keep normalization off by default and explain silence
  if MASTER is zero. Do not silently change firmware gain for export.
- A separate render instance starts from a captured revision. Editing during render
  must not change that export. Show progress and Cancel. Real-time fallback is
  clearly labelled; never promise faster-than-real-time rendering before measuring it.
- Per-track stems are a later feature: shared effects can make isolated passes
  differ from the mix. Offer dry stems/shared FX or document the actual strategy;
  do not promise stems that sum exactly until tested.

**MIDI (.mid)** preserves notes, velocities, timing and supported controllers;
it does not contain synthesized audio, samples or arbitrary effects/parameter locks.
Offer tracks and range, tempo, channels and a drum-note map where available.
SMF type 1 has a tempo/meta track and separate selected musical tracks.

The reliable first candidate is **Capture a performance** from firmware-generated
sequencer events, with sample-clock timestamps. It records the notes actually
played, including supported swing/arp/roll/probability results. It is not an export
of the original generative rules. A fixed render uses the same captured revision
and random-state/seed where available; otherwise call it a newly generated take.
Never derive MIDI by recognizing recorded audio or scraping the LCD.

Only enable MIDI export after that engine has a validated event source or sequence
adapter. For unsupported engines explain the limitation and offer WAV/project
instead. Existing physical-key MIDI output alone is not proof of sequencer export.

Final review: filename, contents, duration/range, tracks, format, sample dependencies
and relevant omissions → **Save to Files** or **Share…**, using the system UI.
Do not show “exported” until the destination operation succeeds; cancellation keeps
the prepared output available for retry. Do not make users choose Files vs sharing
before they can inspect what they are exporting.
For sharing, report hand-off to the selected activity, not guaranteed delivery or
storage by another app; dismissing the share sheet alone is not success evidence.

## Engine capability contract and implementation order

Expose structured, versioned capabilities: working-project read/write, original
formats, backup scope, sample codec/slots/capacity/shared bank, MIDI input/output,
sequencer event coverage, deterministic snapshot and supported render ranges.
Native source functionality does not imply that our existing ABI exposes it.
Disabled/absent UI follows this contract, not hard-coded firmware-name guesses.

Source audit of the current pins (these are adapter opportunities, **not shipped
app features**):

| Engine | User sample storage | Existing note-event source for MIDI take |
| --- | --- | --- |
| SLOOP 2.7.1 | 4 × 80 KiB FSMP slots | Sequencer/arp/roll output; needs host queue and timestamps |
| Felucca 1.6.1 | 3 × 80 KiB slots | Only live-key output found; sequence observer needed |
| X0X 1.1.0 | 3 × 80 KiB break-loop slots | Sequencer sink exists; wrapper currently discards output bytes |
| Melodee 1.4.3 | User sample slots retired | Live chord/strum output found; not a general sequence exporter |
| Official Preview V13 | 8 pads in a shared SEA bank | Outbound send is a stub; observer needed |
| Skiff 1.3.2 | 3 × 80 KiB slots; persistent slice metadata reduces audio capacity | Live keys only; sequencer output requires additional work |
| FoMni 0.4 | No user sample slots | Performed chord-harp/rhythm notes; no user-pattern sequencer |
| Jangada 1.0.1 | 3 × 80 KiB slots | Sequencer output exists; host drain is missing |

All eight still need public, typed project/sample/MIDI interfaces. Equal flash
lengths are not a compatibility check: validate engine identity, pinned version,
schema and checksums before restoring. Private source-line audit and hashes are
recorded in ignored `Research/StorePrep/io-capabilities.json`.

1. **SLOOP vertical slice:** capture current work safely, named project copies and
   complete backup/restore; WAV preview/trim/import into its four sample slots.
   Validate reopen and sample playback before adding more firmware adapters.
2. **Musical output:** recoverable live WAV recording; SLOOP MIDI performance
   capture with timing and coverage tests. Then deterministic offline range export
   if its snapshot/transport contract passes.
3. **Firmware-specific interchange:** Skiff project/pattern/sample workflows;
   Official Preview project/timbre/DX7/bank formats; other pinned engines by their
   actual source APIs. Never use the current V14 manual as a V13 compatibility claim.
4. **Later:** stems, microphone recording, connected hardware transfer and external
   MIDI/Bluetooth routing. These do not block local project/sample/WAV workflows.

All engine access stays on its serial worker. The audio callback only consumes
preallocated audio and, for recording, publishes bounded data to a file-writing
worker; no file I/O, codec work, UI updates, allocation or locks in the callback.
An overflowing recording/event queue must report an incomplete take and preserve
the recoverable part; never silently call a dropped-event MIDI/audio file complete.
Imports use temporary staging, content validation and an atomic commit. Bound
decoded sizes and validate paths, versions and checksums before modifying state.

## Acceptance before shipping

- Export the unsaved current project, reopen it in a clean instance and compare
  notes, edits, timbres, sample dependencies and resulting audio. Persistent flash
  alone is insufficient evidence.
- Test import cancel, unsupported format/version, missing samples, full storage,
  interrupted writes and replacement rollback without losing the current work.
- Verify every sample slot, maximum encoded capacity, trim endpoints, stereo→mono,
  rate conversion and original editor/device round-trip where claimed.
- Compare exported MIDI against engine-generated note-on/off timestamps, velocity,
  channels, tempo changes, swing, rolls, ties, probability and stop/end cleanup;
  independently inspect the .mid in a DAW. Unsupported controls are disclosed.
- WAV performance capture does not glitch the heavy project; long output and
  interruptions leave a playable file. Offline output has the selected start,
  repeats and FX tail and does not mutate live project state.
- Exercise Files/iCloud cancellation and Share destinations, compact/landscape
  layout, Dynamic Type, VoiceOver and explicit destructive-action labels on iPhone.

## Primary references

- [M-VAVE Workbench and current manual](https://open.m-vave.com/fm1-workbench):
  separate project/timbre/DX7/sample-bank interchange, shared sample replacement.
- [Pinned Official V13 simulator](https://github.com/m-vave/fm1_open/blob/b178ac43c25f010c60a878056fb5331fe693fd62/web/engine/Simulator.c):
  working-project export/import and bank APIs exist upstream, absent from our adapter.
- [SLOOP guide](https://github.com/isod89/sloop-fm1/blob/main/GUIDE.md): upstream
  workflow reference; our compatibility claims stay pinned to local 2.7.1 sources.
- Apple [file importer](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)),
  [file exporter](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:)),
  [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink),
  [progress](https://developer.apple.com/design/human-interface-guidelines/progress-indicators)
  and [alerts](https://developer.apple.com/design/human-interface-guidelines/alerts).

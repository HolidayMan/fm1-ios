# Resetting an instrument

The counterclockwise arrow in the expanded top bar resets the selected native
instrument to its compiled initial state. A destructive confirmation names the
instrument. Internal work, save slots, sounds and settings are cleared; other
instruments and named copies in the app library are retained.

Save pending edits inside the firmware before resetting. The recovery image is
the engine's saved-data image, not a snapshot of all live memory. For example,
Hortator uses manual Save slots and JIANT's Restore Last setting affects startup.

During the same app session, touch and hold the reset arrow and choose Restore
pre-reset saved data to recover the last reset's saved data. The action is offered
only for that instrument. Restore asks for confirmation and consumes this session's
recovery action. Recovery files are retained privately; no persistent recovery
browser or undo of a completed restore is promised.

Reset and restore stage and verify their recovery images before replacing the
active native engine. The replacement bypasses older-version migration. The
operation preserves the current host playback intent, volume and panel finish.
The app blocks overlapping loads, imports, sample audition and reset operations.

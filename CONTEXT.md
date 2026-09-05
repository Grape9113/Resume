# Resume

Resume is an opinionated, menu-bar-only Audiobookshelf client optimized for reaching and controlling one audiobook with minimal interaction.

## Language

**Resume panel**:
The application's only interface surface, opened from its menu-bar item. Player, search, settings, connection, and recovery are modes within this panel rather than separate windows.
_Avoid_: Popover, toolbar window, main window, Settings window

**Active audiobook**:
The audiobook currently selected in Resume: normally the one playing, otherwise the last one selected or played.
_Avoid_: Current page, selected result

**Selected library**:
The single Audiobookshelf audiobook library chosen during connection. Resume searches and plays from this library until the user signs out and connects again.
_Avoid_: Active library, library filter

**Connection**:
Resume's remembered relationship with one Audiobookshelf server, user account, and selected library. It includes securely stored credentials so expired server sessions can be re-established with minimal listener involvement.
_Avoid_: Account, server profile

**Known position**:
A playback position Resume has observed locally or from Audiobookshelf that differs from another plausible position by at least 30 seconds. Known positions form a short-lived recovery buffer, not listening history.
_Avoid_: Conflict, backup timestamp

**Position recovery**:
A temporary choice among distinct known positions, offered only when Resume may have selected the wrong position. Recovery remains available for approximately one hour after playback begins and otherwise occupies no interface space.
_Avoid_: Playback history, position history

Before playback begins, recovery positions remain until resolved or Resume exits. Playback starts a one-hour expiry period, a newly detected ambiguity restarts it, and sign-out clears it. Force Fetch and Force Push preserve the displaced position during this period.

**Authoritative position**:
The known position Resume uses by default for the active audiobook. When state is uncertain, the Audiobookshelf server position is authoritative unless the listener explicitly chooses another known position.
_Avoid_: Correct position, winning position

**Force Fetch**:
An explicit command that retrieves the latest Audiobookshelf position and makes it authoritative without beginning playback.
_Avoid_: Refresh, pull

**Force Push**:
An explicit command that makes the Mac's current position authoritative on Audiobookshelf, even when normal synchronization would avoid overwriting server state.
_Avoid_: Sync, upload

**Player mode**:
The normal Resume panel mode showing the active audiobook and its essential playback controls.
_Avoid_: Home, now-playing page

**Book progress**:
The active audiobook's current position across the entire book, independent of chapter boundaries. Resume displays Book progress with a read-only progress bar that cannot seek.
_Avoid_: Chapter progress, scrubber

**Chapter navigation**:
The deliberate way to move to a structurally identified part of an audiobook. Resume does not use its progress bar for position changes.
_Avoid_: Scrubbing, progress-bar seeking

**Search mode**:
The transient Resume panel mode entered by printable typing, showing exactly one best-matching audiobook until accepted or cancelled.
_Avoid_: Search page, results list

**Settings mode**:
The Resume panel mode opened and closed with Control-comma, with Escape also returning to Player mode.
_Avoid_: Settings window, preferences window

## Playback conventions

**Skip backward**:
Move the active audiobook 15 seconds earlier.

**Skip forward**:
Move the active audiobook 30 seconds later.

**Playback speed**:
A per-audiobook preference chosen from 0.75×, 1×, 1.25×, 1.5×, 1.75×, 2×, 2.5×, and 3×. A book without a saved preference defaults to 2×.

**Recently finished**:
The five-day state entered when playback proceeds at or beyond 95% of an audiobook. During this state the book remains at its near-end position and carries a small accessible cover badge.
_Avoid_: Completed, archived

When Recently finished expires, Resume clears the Audiobookshelf finished state and resets its position to the beginning. Before resetting, Resume verifies that the server still reports the book as finished at or beyond 95%; a newer position below 95% means another listen has begun and must be preserved. Replaying the ending does not restart the five-day period. The displaced ending position remains temporarily available through Position recovery.

# Resume

Resume is a menu-bar Audiobookshelf client centered on reaching and controlling one audiobook. This file defines its language; product rules belong in the [current specification](docs/specification.md).

## Language

**Resume panel**:
The application's interface surface, whose modes include Connection, Player, Search, Settings and Chapter navigation.
_Avoid_: Main window, Settings window, search page

**Active audiobook**:
The audiobook Resume currently presents and controls, normally the one playing or most recently selected.
_Avoid_: Current page, selected result

**Selected library**:
The single Audiobookshelf audiobook library within the Connection that supplies Resume's search index.
_Avoid_: Active library, library filter

**Connection**:
Resume's remembered relationship with one Audiobookshelf server, user account and Selected library.
_Avoid_: Account, server profile

**Player mode**:
The panel mode showing the Active audiobook and its essential listening controls.
_Avoid_: Home, now-playing page

**Search mode**:
The transient panel mode for entering text and considering one best-matching audiobook before accepting or cancelling it.
_Avoid_: Results list, library browser

**Settings mode**:
The panel mode containing Connection information and the small set of application settings.
_Avoid_: Preferences window, settings dashboard

**Book progress**:
The read-only position indicator across the entire audiobook.
_Avoid_: Chapter progress, scrubber

**Chapter navigation**:
A deliberate position choice among the audiobook's named chapter boundaries.
_Avoid_: Scrubbing, progress-bar seeking

**Skip backward / Skip forward**:
The fixed backward and forward position changes exposed by the playback controls.
_Avoid_: Rewind mode, fast-forward mode

**Playback speed**:
The listening-rate preference associated with an audiobook.
_Avoid_: Global speed setting

**Playing intent**:
The listener's current request for audio to play, which can remain present while a stream is preparing or recovering.
_Avoid_: Persisted autoplay, observed playback rate

**Known position**:
A materially distinct plausible listening position retained temporarily for recovery, with its source and observation time.
_Avoid_: Listening history, backup timestamp

**Authoritative position**:
The position Resume currently uses as the basis for reconciliation or an explicit synchronization decision.
_Avoid_: Correct position, winning position

**Position recovery**:
The temporary choice among Known positions offered in the synchronization menu.
_Avoid_: History page, permanent bookmarks

**Suspended synchronization**:
The state in which automatic progress writes are held pending an authority decision; local playback can continue.
_Avoid_: Paused playback, disconnected server

**Force Fetch**:
The listener's explicit choice to adopt Audiobookshelf's listening position.
_Avoid_: Refresh, pull

**Recently finished**:
The temporary post-completion state identifying a book whose ending remains available for replay before guarded reset.
_Avoid_: Archived, permanently completed

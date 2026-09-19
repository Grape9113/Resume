---
status: accepted
---
# Server authority with recoverable local alternatives

Audiobookshelf is shared with other clients but its ordinary progress writes have no atomic compare-and-swap protection. Resume therefore uses server baselines, fetch-before-write and suspended automatic synchronization when authority is uncertain, retaining materially different positions for an explicit local recovery or Force Fetch/Push choice. This deliberately trades automatic last-writer-wins convenience for recoverability; it cannot eliminate backend races.

This reconstructs [the original specification](https://github.com/Grape9113/Resume/issues/1) and commit `fcab5aa`, which explicitly suspended writes after recovery selection. Playback and write authority remain separate: detecting another active client's position need not stop local audio. Recovery lifetimes are product policy in the current specification, not permanent listening history.

Amended by [the September 19 player refinement](https://github.com/Grape9113/Resume/issues/11): Force Push is no longer a user control. Pause requests automatic synchronization through the guarded session-close path. Force Fetch and recovery choices remain; automatic pause synchronization does not bypass suspended authority or overwrite a conflicting server position.

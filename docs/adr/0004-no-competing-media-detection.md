---
status: accepted
---
# Omit competing-media auto-pause

Resume intentionally omits automatic pausing in response to other applications' media. The recorded product decision was that supported low-permission macOS signals did not reliably distinguish meaningful playback from incidental sound; audio capture, private MediaRemote APIs and process inspection were unacceptable trade-offs for this utility. Output-device removal remains a separate supported pause condition.

Reconstructed from the explicit reasoning and exclusions in [the original specification](https://github.com/Grape9113/Resume/issues/1). This records that decision, not a new survey of current macOS capabilities. `M` is searchable text, not a reserved media-detection shortcut.

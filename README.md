# Resume

A compact native macOS menu-bar audiobook client for Audiobookshelf.

## Run

Double-click `Build Resume.command`, or open this folder's `Package.swift` in Xcode and run the `Resume` executable.

The packaged application is written to `.build/Resume.app`. Resume is locally ad-hoc signed and intended for personal use on macOS GoldenGate.

## Develop

```sh
swift test
./Scripts/build-app.sh
```

The product specification is [GitHub issue #1](https://github.com/Grape9113/Resume/issues/1). Domain language is defined in `CONTEXT.md`.

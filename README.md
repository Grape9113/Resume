# Resume

A compact native macOS menu-bar audiobook client for Audiobookshelf.

## How to run Resume

1. Open `Resume.xcodeproj` in Xcode.
2. Make sure the `Resume` scheme is selected, then press Xcode's Run button (the triangle).
3. To stop Resume, press Xcode's Stop button (the square).
4. Open Resume from the menu bar and look at the version, build number, and build time at the bottom. The newest build has the latest build time.

Xcode automatically stops any running copy of Resume before it launches the new build. Use only this Xcode project to build and run the app.

The product specification is [GitHub issue #1](https://github.com/Grape9113/Resume/issues/1). Domain language is defined in `CONTEXT.md`.

## Tests

Use Xcode's Product → Test, or run:

```sh
xcodebuild test -project Resume.xcodeproj -scheme Resume -destination 'platform=macOS,arch=arm64'
```

See [testing boundaries and remaining acceptance checks](docs/testing.md). The UI tests use an isolated Debug-only panel host and do not need your Audiobookshelf credentials.

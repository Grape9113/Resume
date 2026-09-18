# Resume

A compact native macOS menu-bar audiobook client for Audiobookshelf.

## How to run Resume

1. Open `Resume.xcodeproj` in Xcode.
2. Make sure the `Resume` scheme is selected, then press Xcode's Run button (the triangle).
3. To stop Resume, press Xcode's Stop button (the square).
4. Open Resume from the menu bar and look at the version, build number, and build time at the bottom. The newest build has the latest build time.

Xcode automatically stops any running copy of Resume before it launches the new build. Use only this Xcode project to build and run the app.

The [current specification](docs/specification.md) describes the intended existing product. Start with the [baseline and remaining discrepancies](docs/baseline.md) before changing behavior; [issue #1](https://github.com/Grape9113/Resume/issues/1) is historical completed work.

## Project knowledge

- [Domain glossary](CONTEXT.md): product language.
- [Architecture and decisions](docs/architecture.md): actual state owners, integration seams and constraints.
- [Development workflow](docs/workflow.md): artifact authority and the `to-tickets → implement → code-review` loop.
- [Retrospective](docs/retrospectives/2026-09-18-workflow-recovery.md): lessons from implementation and workflow recovery.

## Tests

Use Xcode's Product → Test, or run:

```sh
xcodebuild test -project Resume.xcodeproj -scheme Resume -destination 'platform=macOS,arch=arm64'
```

See [testing boundaries and remaining acceptance checks](docs/testing.md). The UI tests use an isolated Debug-only panel host and do not need your Audiobookshelf credentials.

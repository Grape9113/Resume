# Testing Resume

The acceptance source is the [current specification](specification.md). The [baseline register](baseline.md) distinguishes intended behavior from known discrepancies and links the remaining work. Historical issue #1 is not a new build plan.

Run the complete automated suite through the Xcode project:

```sh
xcodebuild test -project Resume.xcodeproj -scheme Resume -destination 'platform=macOS,arch=arm64'
```

For the fast application, service, and policy tests:

```sh
xcodebuild test -project Resume.xcodeproj -scheme Resume -destination 'platform=macOS,arch=arm64' -only-testing:ResumeCoreTests
```

Build the normal release application:

```sh
xcodebuild build -project Resume.xcodeproj -scheme Resume -configuration Release -destination 'platform=macOS,arch=arm64'
```

Run UI tests serially. They use the desktop's keyboard and pointer; leave the test window in front while they run.

## Test boundaries

`AppModelTests` exercises the shipped application model with controlled Audiobookshelf, playback, credentials, persistence, and clock dependencies. The test target compiles the same application sources as Resume. It does not substitute the unused core panel-transition helper for the shipped application.

Application regressions cover cancellation during playback loading, pause intent, closing the previous session during book selection, server-provided session start positions, stale recovery responses, wake and reconnect synchronization, concurrent-client progress, guarded recovery choices, recovery expiry, completion boundaries, replay after an expired finished marker, sign-out, and callbacks from an unloaded player.

The HTTP tests exercise the actual `AudiobookshelfClient` through `URLSession` fixtures, including delayed concurrent 401 responses and invalid-password recovery. Token-envelope fixtures follow the [Audiobookshelf authentication implementation](https://github.com/advplyr/audiobookshelf/blob/master/server/Auth.js). These are controlled protocol tests, not a live PikaPods integration test.

The cache and playback adapter tests cover caching again after sign-out and retaining the selected playback speed while paused. Existing policy, authentication, search, contract, retry, and ledger tests remain part of the suite.

The playback performance regressions use real AVFoundation and generated silent audio with a controlled range-serving transport. They exercise one-hour single-file and three-part books, resume in the middle of the book, require preparation in under one second, and verify that playback time advances. Each transport response has 10 ms of synthetic latency; these are local regression budgets, not measurements of PikaPods response times. Startup must use bounded requests and transfer less than 4 MiB per part before playing. Unloading must stop further transfers. A separate test verifies cancellation of an in-flight metadata fetch.

The artwork test publishes real `MPMediaItemArtwork` and requests its image from a background task. This reproduced the executor assertion observed in the running Resume process before the fix; a simulated player cannot catch it.

`ResumePanelTests` runs the actual `ResumePanel` in a Debug-only test host with in-memory services. `--ui-testing` creates this isolated host; normal launches use `MenuBarExtra`, and Release excludes the host and its fixtures. The host avoids menu-manager positioning and credential prompts. It verifies typing and editing, Settings shortcuts, Escape, selection without autoplay, Space, and pointer interaction with read-only Book progress.

## Acceptance still requiring the real environment

Passing this suite does not establish complete product acceptance. The following need separate verification:

- Menu-bar opening/dismissal, layout, and focus with the user's menu-bar manager. The automated panel host does not assert menu-bar placement or lifecycle.
- Credentialed login and rotating sessions against the deployed PikaPods version; direct/HLS authenticated audio, multipart playback, socket delivery, and session close behavior on a disposable Audiobookshelf server.
- Actual sleep/wake, network loss, output-device removal, Control Center/media keys, Launch at Login, VoiceOver, Full Keyboard Access, and text composition with the user's keyboard/input method.
- Idle resource use and cache/network behavior with a representative library.

No production credentials or server progress are needed by the automated tests. Do not infer that every current specification story is covered merely because the suite passes.

## Verified run: 2026-09-17

On macOS 27 with Xcode 27.0 (27A5237l), the complete Debug test action passed: 55 tests, including 4 UI tests, with zero failures and zero skips. Parameterized tests produced 63 individual executions. The Release application build also passed. `git diff --check` reported no whitespace errors.

## Playback diagnosis: 2026-09-18

The following faults were reproduced before fixing them:

- `AuthenticatedAssetLoader` forwarded AVFoundation's open-ended `bytes=0-` request to a transport that buffers the whole response. A one-hour fixture failed before it could become readable. The loader now delivers at most 256 KiB per request incrementally, consistent with [Apple's resource-loader contract](https://developer.apple.com/documentation/avfoundation/avassetresourceloadingdatarequest/requestsalldatatoendofresource). Replaced or unloaded assets explicitly cancel their outstanding requests.
- The system artwork handler inherited `MainActor` isolation even though MediaPlayer invoked it on a background queue. Sampling the running app found it stopped at that assertion; the new regression also crashed before the fix. The handler now captures immutable pixels in a nonisolated factory and creates an image for each system request.

- The complete test run also exposed a crash inside AppKit's image-format lookup during concurrent cache reads. Cache decoding now uses ImageIO off the main actor, caps decoded covers at 1024 pixels, and creates their UI images on the main actor. A concurrent save/read regression covers this path.

These tests do not establish startup timing against a live account, every media codec, or large numbers of separate audio tracks. Normal AVPlayer read-ahead still occurs during playback; the performance budget measures preparation before playback.

## Verified playback-fix run: 2026-09-18

On macOS 27 with Xcode 27.0, all 56 core test functions passed with three repetitions (`-only-testing:ResumeCoreTests -test-iterations 3`), including both real-playback cases. The Release build passed and `git diff --check` was clean.

After the user dismissed the blocking macOS security dialog, the isolated UI suite passed all four tests with zero failures in 32 seconds (`-only-testing:ResumeUITests`). All 60 test functions are therefore green for this revision: 56 core tests and 4 UI tests. The core and UI suites were run separately; live-account playback latency remains unverified.

## Operating the verification loop

Use the same project and scheme as the application. Run Xcode test invocations serially, including core/UI subsets; overlapping runners can interfere with desktop focus and results. Use Xcode Stop for a debugger-stopped Resume before running UI tests. If a macOS security dialog owns keyboard focus, stop keyboard automation and let the user handle the dialog; the isolated UI host requires no account credentials or Keychain grant.

For a suspected media problem, measure through the real native adapter with controlled media and transport before inferring performance from the simulated player. For a state transition, start at `AppModel`. Older `ResumeApplication`, `Authenticator` and `SynchronizationPolicy.reconcile` helper tests are narrower policy evidence. Preserve the distinction when reporting coverage.

The fixture's one-second preparation, byte-transfer budget, 10 ms response latency, 256 KiB request cap and image-size assertion are local regression/implementation choices. They are not a universal latency SLA, media-format acceptance matrix or immutable product dimensions. Documentation-only reconciliation does not require replaying credentialed or hardware tests; verify unchanged production/test/build files and audit claims against the dated evidence instead.

## Player refinement: September 19

Issue #11 adds application regressions for initial-position ownership, transient progress failures, loading completion/failure, pause/periodic-sync coalescing, inline credential recovery on pause, and network recovery during preparation. The isolated UI host verifies compact bounds, removal of Force Push, visible loading, and existing keyboard interactions. Its ordinary-window activation policy is Debug-only and does not change the production menu-bar app.

The controlled startup trace separates two 100 ms service responses and 100 ms player preparation (approximately 316 ms total). A faster concurrent service-request experiment was rejected because it could pair an older session position with a newer server baseline. Instead, bounded concurrent multipart metadata loading reduced three-part native preparation from 128 ms to 43 ms in the controlled media fixture. These are fixture results, not PikaPods or audible-output latency guarantees. Native AVPlayer tests separately verify stable position publication, seek/start, advancing playback time, and the full application-to-player path. Media transfer, server processing and decoder/audio-device startup still impose real latency; this is not a large-library performance claim.

Verified on September 19 with macOS 27/Xcode 27: all 64 core test functions and all five UI tests passed in one serial test action. The full application-to-native-player fixture, including two 100 ms service responses, prepared in 212 ms and observed actual playback at 555 ms. The panel screenshots show the compact cover-led layout without a panel-wide focus ring. The startup warning and zero-position regressions were reproduced before their fixes. The Release application build and `git diff --check` also passed.

## Native Settings and conflict recovery: September 19

Amendment #12 and tickets #13–#14 use the same AppModel, native-player and UI seams. Command-comma first failed against the previous implementation, then passed through a native Settings scene. UI coverage now checks Player and Search shortcuts, the app-menu command, window reuse, metadata placement, absence of the synchronization menu, and conflict-only recovery that disappears after a choice while alternatives remain in Settings. The Debug host is a SwiftUI Window scene so it exercises actual Settings command routing, rather than a detached hosting controller. This does not extend the test claim to third-party menu-bar managers.

Application regressions reproduced recovery remaining suspended after selection and an older recovered position being authorized after the server moved before Play. Guarded resolution now checks the presented server alternative, rejects a stale book response, preserves suspension across a later server change, and does not autoplay or directly force a write. Obsolete Force Fetch tests were replaced by recovery/automatic-reconciliation coverage.

The final serial test action passed all 67 core test functions and eight UI tests on macOS 27/Xcode 27. The controlled application-to-native-player path prepared in 207 ms and observed playback in 537 ms, including two 100 ms service responses; this remains fixture evidence, not measured live-server audible latency. Screenshots of normal Player, conflict Player and Settings were inspected. The existing focus, quiet transient failure, stable position, loading and coalesced pause-sync regressions remain green.

The Release application build and `git diff --check` passed. Remaining native-environment checks above and baseline follow-ups #3–#10 remain separate; this run did not use production credentials or modify a live audiobook position.

The two-axis review prompted additional red/green checks for recovery busy-state ownership across book selection and server convergence with a chosen position. A further regression keeps first-Play chapter selection independent of pending recovery authority. The counts above include the final rerun after these corrections. Swift Testing filters that accidentally select zero tests are not evidence; verify the executed test count in the log.

A final extension of the recovery regression verifies selecting a retained Settings alternative after automatic synchronization. It reproduced an unnecessary re-prompt caused by comparing against an old retained server alternative. Resolved choices now compare against the confirmed synchronization baseline; unresolved conflicts still compare against the presented server choice. All 67 core tests passed again after this model-only correction; the eight UI tests passed in the preceding combined run.

## Compact red interface: September 22

Accepted amendment [#15](https://github.com/Grape9113/Resume/issues/15), executed through #16–#18, uses the existing AppModel and native panel seams. The compactness regression first failed at the old 304 × 450-point host window. The in-place Settings regression first failed because metadata remained in a separate window. A Connection regression also reproduced Enter failing to submit the form. These checks pass with the new 280 × 306-point content shell (280 × 338 including the Debug host title bar), in-panel Settings and keyboard submission.

The full serial Xcode test action passed **67 core test functions and 11 UI tests** on macOS 27/Xcode 27 at `647f663`. Coverage includes existing native playback/synchronization regressions; same-window Settings from Player, Search and Chapters; repeated commands and Escape; Connection validation and required-setup return; one-result/no-match Search; chapter selection without autoplay; read-only progress; loading and conflict recovery; and stable bounds across representative modes. The Settings application test also verifies unchanged playing intent/selection and preservation of Connection/library prerequisites. An initial narrow Swift Testing filter selected zero tests; it was discarded as evidence and the complete AppModel suite was run successfully before the final suite.

Native test-host captures were visually inspected for light/dark Player, square/portrait/missing artwork, Search candidate/no-match, Settings, Chapters, long library names, Connection validation, playback errors and conflict/retained recovery choices. Inspection caught low-contrast Connection placeholders, a clipped recovery choice and a fixed-size missing-artwork symbol overflowing the reduced conflict artwork area. The first two were corrected before the full suite. The final placeholder correction at `a7fa92b` passed a further focused conflict/recovery UI run, and its screenshot was inspected. A final Release build and Swift formatting/whitespace checks passed after that correction.

[Player capture](design/resume-player-test-host.png) is from the Debug host, using synthetic artwork; its title bar is not part of the menu-bar product. The [approved reference](design/resume-ui-reference.jpg) remains the visual design source. Both independent code-review axes reported zero remaining findings against `cd93e2741f6dfbde1c87bae7f0ae7f89cb5c5344` through `a7fa92b`.

A fixture-backed native inspection was attempted after automated checks, but the computer-use tool did not reliably expose the status item (SystemUIServer inspection timed out). This does **not** certify production menu-bar presentation, dismissal/reopening, menu-manager integration or closed-panel command routing. Full Keyboard Access, VoiceOver, input composition and live-account/device acceptance retain the existing boundaries above and in #8. No live credentials or server progress were used.

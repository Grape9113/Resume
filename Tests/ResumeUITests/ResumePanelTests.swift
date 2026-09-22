import AppKit
import XCTest

@MainActor
final class ResumePanelTests: XCTestCase {
  private func openPlayer() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    app.activate()
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    capture.name = "Player panel"
    capture.lifetime = .keepAlways
    add(capture)
    return app
  }

  func testCommandCommaOpensSettings() {
    let app = openPlayer()
    let playerWindow = app.windows["Resume UI Test Panel"]
    XCTAssertFalse(playerWindow.staticTexts["build-information"].exists)
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["build-information"].exists)
    app.typeKey(",", modifierFlags: .command)
    XCTAssertEqual(app.windows.containing(.staticText, identifier: "Settings").count, 1)
    XCTAssertTrue(playerWindow.staticTexts["build-information"].exists)
    XCTAssertEqual(app.windows.count, 1)
    XCTAssertFalse(app.buttons["Back"].exists)
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(playerWindow.buttons["Play"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["Settings"].exists)
  }

  func testAppMenuOpensSameSettings() {
    let app = openPlayer()
    app.menuBars.menuBarItems["Resume"].click()
    app.menuItems["Settings…"].click()
    XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["build-information"].exists)
    XCTAssertTrue(app.checkBoxes["Launch at Login"].exists)
    XCTAssertTrue(app.buttons["Sign Out"].exists)
  }

  func testCompactPlayerHasAutomaticSyncAndLoadingFeedback() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--delayed-playback"]
    app.launch()
    app.activate()
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    XCTAssertLessThan(app.windows.firstMatch.frame.width, 290)
    XCTAssertLessThan(app.windows.firstMatch.frame.height, 340)
    XCTAssertFalse(app.menuButtons["Synchronization"].exists)
    XCTAssertFalse(app.staticTexts["Choose listening position"].exists)
    XCTAssertFalse(app.staticTexts["build-information"].exists)
    app.buttons["Play"].click()
    let loading = app.activityIndicators["Loading playback"]
    XCTAssertTrue(loading.waitForExistence(timeout: 2))
    XCTAssertTrue(loading.waitForNonExistence(timeout: 6))
    XCTAssertTrue(app.buttons["Pause"].exists)
    let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    capture.name = "Compact player"
    capture.lifetime = .keepAlways
    add(capture)
  }

  func testConflictChoicesDisappearAfterResolutionAndRemainInSettings() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--position-conflict"]
    app.launch()
    app.activate()
    let conflict = app.staticTexts["Choose listening position"]
    XCTAssertTrue(conflict.waitForExistence(timeout: 5))
    XCTAssertFalse(app.menuButtons["Synchronization"].exists)
    let before = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    before.name = "Player with unresolved conflict"
    before.lifetime = .keepAlways
    add(before)
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "This Mac")).firstMatch.click()
    XCTAssertTrue(conflict.waitForNonExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Play"].exists)
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(app.staticTexts["Other listening positions"].waitForExistence(timeout: 3))
    let settings = app.windows.containing(.staticText, identifier: "Settings").firstMatch
    let after = XCTAttachment(screenshot: settings.screenshot())
    after.name = "Settings with retained alternatives"
    after.lifetime = .keepAlways
    add(after)
  }

  func testSpaceControlsPlaybackAndProgressCannotSeek() {
    let app = openPlayer()
    let progress = app.progressIndicators["Book progress"]
    XCTAssertNotNil(progress.value)
    let original = String(describing: progress.value)
    progress.click()
    let start = progress.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
    let end = progress.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: end)
    XCTAssertEqual(String(describing: progress.value), original)
    app.typeText(" ")
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
    app.typeText(" ")
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
  }

  func testUppercaseTypingAndEscape() {
    let app = openPlayer()
    app.typeText("M")
    let search = app.textFields["Search"]
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    XCTAssertEqual(search.value as? String, "M")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
  }

  func testSearchEditingAndModeShortcuts() {
    let app = openPlayer()
    app.typeText("ranger apprentice")
    let search = app.textFields["Search"]
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    XCTAssertEqual(search.value as? String, "ranger apprentice")
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    XCTAssertFalse(search.exists)
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
    app.typeText("m")
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    app.typeKey(.delete, modifierFlags: [])
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
    XCTAssertFalse(search.exists)
    app.typeText("ranger")
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
  }

  func testPrintableInputStartsSearch() {
    let app = openPlayer()
    app.typeText("m")
    let search = app.textFields["Search"]
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    XCTAssertEqual(search.value as? String, "m")
  }
  func testConnectionKeyboardSubmissionAndSettingsReturn() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--connection-mode"]
    app.launch()
    app.activate()
    let server = app.textFields["https://your-pod.pikapod.net"]
    XCTAssertTrue(server.waitForExistence(timeout: 5))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(server.exists)
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(server.waitForExistence(timeout: 3))
    server.click()
    server.typeText("http://example.test")
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(
      app.staticTexts["Enter your PikaPods server address."].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Connect"].isHittable)
    let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    capture.name = "Connection validation"
    capture.lifetime = .keepAlways
    add(capture)
  }

  func testChaptersAndSearchKeepTheSameShell() {
    let app = openPlayer()
    let size = app.windows.firstMatch.frame.size
    app.buttons["Chapters"].click()
    XCTAssertTrue(app.staticTexts["Chapters"].exists)
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
    app.buttons["Chapters"].click()
    let chapter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Chapter Two"))
      .firstMatch
    XCTAssertTrue(chapter.waitForExistence(timeout: 3))
    capture(app, "Chapters")
    chapter.click()
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
    XCTAssertEqual(app.windows.firstMatch.frame.size, size)
    app.typeText("ranger")
    XCTAssertTrue(app.staticTexts["John Flanagan"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["Play"].exists)
    XCTAssertEqual(app.windows.firstMatch.frame.size, size)
    capture(app, "Search candidate")
    app.typeKey("a", modifierFlags: .command)
    app.typeText("zzzzzzzzzzzzzz")
    XCTAssertTrue(app.staticTexts["No match"].waitForExistence(timeout: 3))
    capture(app, "Search no match")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
  }

  func testAppearanceAndLongContentRemainUsable() {
    for dark in [false, true] {
      for mode in [
        "--square-artwork", "--portrait-artwork", "--library-mode", "--player-error",
        "--empty-player",
      ] {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", mode] + (dark ? ["--dark-appearance"] : [])
        app.launch()
        app.activate()
        let control = mode == "--library-mode" ? app.buttons["Audiobooks"] : app.buttons["Play"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertTrue(control.isHittable)
        XCTAssertLessThan(app.windows.firstMatch.frame.width, 290)
        XCTAssertLessThan(app.windows.firstMatch.frame.height, 340)
        capture(app, "\(mode) \(dark ? "dark" : "light")")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
        capture(app, "Settings \(dark ? "dark" : "light")")
        app.terminate()
      }
    }
  }

  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

}

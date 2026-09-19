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
    XCTAssertFalse(playerWindow.staticTexts["build-information"].exists)
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
    XCTAssertLessThan(app.windows.firstMatch.frame.width, 330)
    XCTAssertLessThan(app.windows.firstMatch.frame.height, 480)
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
    app.typeKey("w", modifierFlags: .command)
    app.windows["Resume UI Test Panel"].click()
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
}

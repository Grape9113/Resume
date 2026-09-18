import AppKit
import XCTest

@MainActor
final class ResumePanelTests: XCTestCase {
  private func openPlayer() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    return app
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
    app.typeKey(",", modifierFlags: .control)
    XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    XCTAssertFalse(search.exists)
    app.typeKey(",", modifierFlags: .control)
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

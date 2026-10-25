import XCTest

/// Walks every screen a new user sees and saves a screenshot of each.
/// Doubles as a smoke test: every tap below must find its control.
///
///     SCREENSHOT_DIR=build/screenshots xcodebuild test -scheme HomeStep \
///       -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' -only-testing:HomeStepUITests
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// `name` starts with its order, e.g. "1-guide".
    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")
            try? png.write(to: url)
        }
    }

    func testOnboardingThenSetUpAPlace() {
        app.launchArguments = ["-settings.onboardingDone", "NO", "-resetPlaces"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to HomeStep"].waitForExistence(timeout: 5))
        shot("2-welcome")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["HomeStep supplements your cane"].waitForExistence(timeout: 3))
        shot("3-safety")
        app.buttons["I understand"].tap()
        XCTAssertTrue(app.staticTexts["Camera and mounting"].waitForExistence(timeout: 3))
        shot("3b-mounting")
        let holder = app.descendants(matching: .any)["See the phone holder we use"]
        if !holder.isHittable { app.swipeUp() }
        XCTAssertTrue(holder.exists, "the holder link must be on the mounting page")
        let allow = app.buttons["Allow camera and start"]
        if !allow.isHittable { app.swipeUp() }
        allow.tap()
        // Camera permission alert (Simulator): allow if shown.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowAlert = springboard.buttons["Allow"]
        if allowAlert.waitForExistence(timeout: 3) { allowAlert.tap() }

        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
        app.buttons["Places"].tap()
        app.buttons["Try the sample place"].tap()
        XCTAssertTrue(app.staticTexts["Sample home"].waitForExistence(timeout: 3))
        shot("4-places")
        app.staticTexts["Sample home"].tap()
        XCTAssertTrue(app.buttons["Print or save markers"].waitForExistence(timeout: 3))
        shot("5-landmarks")
        // Screenshot an existing hazard landmark: shows the step guidance
        // rather than a keyboard.
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Marker 3'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Hear it"].waitForExistence(timeout: 3))
        shot("6-editor")
        app.buttons["Cancel"].tap()

        app.buttons["Add landmark"].tap()
        let name = app.textFields["Name, e.g. Kitchen door"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("Back door")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Back door'")).firstMatch
            .waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to Places
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to Guide
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Speak landmarks and cues"].waitForExistence(timeout: 3))
        shot("7-settings")
    }

    func testGuideScreen() {
        app.launchArguments = ["-settings.onboardingDone", "YES", "-resetPlaces", "-demoRunning"]
        app.launch()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        shot("1-guide")
    }
}

import XCTest

/// Exercises the real scene callbacks with an explicitly copied, isolated library.
final class PlaybackLifecycleUITests:XCTestCase {
    func testLaunchHomeReturnAndManualPausePolicy() throws {
        let key="FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"
        guard let fixture=ProcessInfo.processInfo.environment[key] else {
            throw XCTSkip("Opt in with a Documents/PerformanceFixtures library; never uses owner files")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchArguments += ["-instrumentHeaderCollapsed","NO"]
        app.launchEnvironment[key]=fixture
        app.launch()
        let pause=app.buttons["Pause instrument"],resume=app.buttons["Resume instrument"]
        XCTAssertTrue(pause.waitForExistence(timeout:15),"Cold launch must request playback")
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:15))
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(pause.waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:15))
        pause.tap()
        XCTAssertTrue(resume.waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout:15))
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(resume.waitForExistence(timeout:15),"Manual Pause must survive Home/return")
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout:15))
        resume.tap()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:15))
        pause.tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout:15))
    }
}

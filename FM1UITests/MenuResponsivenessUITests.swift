import XCTest

/// Repeatable whole-app interaction trace. XCTest timings include its automation
/// overhead; use the attached Instruments recording for main-thread/hitch work.
final class MenuResponsivenessUITests:XCTestCase {
    func testLibrarySearchScrollAndMenusWhilePlaying()throws {
        guard ProcessInfo.processInfo.environment["FM1_PROFILE_MENUS"] == "1",
              let fixture=ProcessInfo.processInfo.environment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"] else {
            throw XCTSkip("Opt-in profiling requires an isolated firmware library")
        }
        guard ProcessInfo.processInfo.environment["FM1_PROFILE_MODE"] != "wasm" else {
            throw XCTSkip("The consumer app is native-only; experimental profiling needs a separate test host")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchArguments += ["-instrumentHeaderCollapsed","NO"]
        app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture
        app.launchEnvironment["FM1_PROFILE_UI"]="1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:30),"The profile requires a playing instrument")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        for _ in 0..<2 {
            element("Firmware library",in:app).tap()
            let search=app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout:10))
            search.tap();search.typeText("SLOOP\n")
            app.collectionViews.firstMatch.swipeUp()
            closeLibrary(in:app)
            element("Panel color",in:app).tap()
            XCTAssertTrue(app.buttons["Finish Black-Green"].waitForExistence(timeout:10))
            if ProcessInfo.processInfo.environment["FM1_PROFILE_PRESERVE_APPEARANCE"] == "1" {
                element("Done",in:app).tap()
            } else {element("Finish Black-Green",in:app).tap()}
            element("About",in:app).tap()
            XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout:10))
            app.collectionViews.firstMatch.swipeUp();element("Done",in:app).tap()
        }
        XCTAssertTrue(app.buttons["Pause instrument"].exists)
        XCUIDevice.shared.press(.home)
    }
    private func element(_ id:String,in app:XCUIApplication)->XCUIElement {
        app.descendants(matching:.any).matching(identifier:id).firstMatch
    }
    private func closeLibrary(in app:XCUIApplication) {
        let done=element("Done",in:app)
        if done.exists && done.isHittable {done.tap();return}
        // iOS 27 presents an expanded search surface with its own Close control.
        let close=element("Close",in:app)
        XCTAssertTrue(close.waitForExistence(timeout:5));close.tap()
        if done.exists && done.isHittable {done.tap()}
        XCTAssertTrue(element("Panel color",in:app).isHittable)
    }
}

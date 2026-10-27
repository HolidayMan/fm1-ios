import XCTest

/// Real public downloads into an explicitly isolated simulator workspace.
final class CommunityFirmwareUITests:XCTestCase {
    private func capture(_ name:String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    private func wait(_ message:String,timeout:TimeInterval=45,_ condition:@escaping()->Bool) {
        let result=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in condition()},object:nil)],timeout:timeout)
        XCTAssertEqual(result,.completed,message)
    }
    private func search(_ text:String,in app:XCUIApplication) {
        let field=app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:10));field.tap()
        let previous=field.value as? String ?? ""
        if field.buttons["Clear text"].exists {field.buttons["Clear text"].tap()}
        else if !previous.isEmpty && previous != "Search" {field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:previous.count))}
        field.typeText(text+"\n")
    }
    func testDownloadsAllNewInstrumentsAndSwitchesWithoutRestart()throws {
        guard let fixture=ProcessInfo.processInfo.environment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"],
              ProcessInfo.processInfo.environment["FM1_COMMUNITY_DOWNLOAD_UI"] == "1" else {
            throw XCTSkip("Requires a dedicated empty simulator fixture and explicit network-download opt-in")
        }
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchArguments += ["-instrumentHeaderCollapsed","NO"]
        app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture
        app.launch()
        for name in ["CoralFlower","AMB-1","GHOULBOX","LOOM-8","Hortator","JIANT FM"] {
            let chooser=app.buttons["Firmware library"]
            XCTAssertTrue(chooser.waitForExistence(timeout:15));chooser.tap()
            search(name,in:app)
            let download=app.buttons["Download \(name)"]
            XCTAssertTrue(download.waitForExistence(timeout:10),"The compiled release must be offered: \(name)")
            if !download.isHittable {app.collectionViews.firstMatch.swipeUp()}
            capture("Catalogue · \(name)")
            download.tap()
            wait("The actual downloaded package must load without a restart: \(name)",timeout:90) {
                !app.navigationBars["Firmware library"].exists && chooser.label.contains(name) && app.staticTexts["Playing"].exists
            }
            XCTAssertFalse(app.alerts.firstMatch.exists)
            XCTAssertFalse(app.buttons["Projects and files"].exists,"SLOOP-only file operations must not be advertised for another engine")
            if app.buttons["C#4"].exists {app.buttons["C#4"].press(forDuration:0.2)}
            app.buttons["C4"].press(forDuration:0.6)
            app.buttons["HOME"].tap()
            capture("Native instrument · \(name)")
            app.buttons["Pause instrument"].tap()
            XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout:10))
            app.buttons["Resume instrument"].tap()
            XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:15))
        }
        app.terminate();app.launch()
        let chooser=app.buttons["Firmware library"]
        XCTAssertTrue(chooser.waitForExistence(timeout:15));chooser.tap();search("CoralFlower",in:app)
        let installed=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","Installed firmware CoralFlower")).firstMatch
        XCTAssertTrue(installed.waitForExistence(timeout:10));installed.tap()
        wait("An installed native instrument must reopen after relaunch") {chooser.label.contains("CoralFlower") && app.staticTexts["Playing"].exists}
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}

import XCTest

/// The consumer app offers only included instruments, including in isolated tests.
final class NativeOnlyUITests:XCTestCase {
    private func element(_ id:String,in app:XCUIApplication)->XCUIElement {
        app.descendants(matching:.any).matching(identifier:id).firstMatch
    }
    private func launch()throws->XCUIApplication {
        guard let fixture=ProcessInfo.processInfo.environment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"] else {
            throw XCTSkip("Requires an isolated Documents/PerformanceFixtures library")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchArguments += ["-instrumentHeaderCollapsed","NO"]
        app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture
        app.launch()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:30))
        return app
    }
    private func capture(_ name:String) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        image.name=name;image.lifetime = .keepAlways;add(image)
    }
    private func scrollTo(_ control:XCUIElement,in app:XCUIApplication) {
        let list=app.collectionViews.firstMatch
        for _ in 0..<20 {
            if control.exists && control.isHittable {return}
            // Short drags avoid skipping an entire row on compact landscape lists.
            list.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.78)).press(forDuration:0.05,thenDragTo:list.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.48)))
        }
    }
    private func search(_ text:String,in app:XCUIApplication) {
        let search=app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:10));search.tap()
        let previous=search.value as? String ?? ""
        if previous != "Find a firmware" {search.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:previous.count))}
        search.typeText(text+"\n")
    }
    func testCuratedLibraryHasDownloadSizesAndNoUnsupportedImport()throws {
        let app=try launch()
        XCTAssertFalse(element("SLOOP engine",in:app).exists)
        XCTAssertFalse(element("Emulator CPU frequency",in:app).exists)
        capture("Consumer instrument panel")
        element("Firmware library",in:app).tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout:10))
        capture("Curated firmware library")
        XCTAssertFalse(app.buttons["Import .fwsc from Files"].exists)
        for name in ["Stock","Hortator"] {
            search(name,in:app)
            XCTAssertFalse(element("Download \(name)",in:app).exists)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",name)).firstMatch.exists)
        }
        search("SLOOP",in:app)
        let download=element("Download SLOOP",in:app),size=element("Download size sloop",in:app)
        XCTAssertTrue(download.waitForExistence(timeout:10))
        XCTAssertTrue(size.exists);XCTAssertTrue(size.label.contains("download"))
        XCTAssertTrue(download.label.contains(","),"VoiceOver must announce the download size before activation")
        capture("Download size before activation")
        XCTAssertFalse(app.staticTexts["Universal WASM · experimental"].exists)
    }
    func testAboutExplainsPreviewAndPrivacyAndLoadsLicensesWithoutDiagnostics()throws {
        let app=try launch()
        element("About",in:app).tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout:10))
        let preview=element("FM1 Open preview information",in:app)
        scrollTo(preview,in:app)
        XCTAssertTrue(preview.exists)
        let privacy=element("Privacy information",in:app)
        scrollTo(privacy,in:app)
        XCTAssertTrue(privacy.exists)
        XCTAssertFalse(app.staticTexts["Audio performance"].exists)
        XCTAssertFalse(app.staticTexts["Firmware engine"].exists)
        XCTAssertFalse(element("Emulator CPU frequency",in:app).exists)
        let license=element("fm1-emu · MIT",in:app)
        scrollTo(license,in:app)
        XCTAssertTrue(license.isHittable);license.tap()
        let text=element("License text",in:app)
        XCTAssertTrue(text.waitForExistence(timeout:10))
        XCTAssertTrue(text.label.contains("Permission"),"The bundled license must actually load")
        let back=app.navigationBars.buttons["About"]
        XCTAssertTrue(back.isHittable);back.tap()
        let thirdParty=element("Skiff · third-party credits",in:app)
        scrollTo(thirdParty,in:app)
        XCTAssertTrue(thirdParty.isHittable);thirdParty.tap()
        XCTAssertTrue(text.waitForExistence(timeout:10))
        XCTAssertTrue(text.label.contains("Apache License"),"The full bundled third-party notice must be reachable")
    }
    func testTransportTargetsAndMuteStateAreAccessible()throws {
        let app=try launch()
        for id in ["Pause instrument","Mute audio","Panel color","About"] {
            let button=element(id,in:app)
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width,44)
            XCTAssertGreaterThanOrEqual(button.frame.height,44)
        }
        let mute=element("Mute audio",in:app)
        mute.tap()
        XCTAssertEqual(mute.label,"Unmute audio")
        XCTAssertEqual(mute.value as? String,"Muted")
        XCTAssertTrue(app.staticTexts["Playing"].exists)
        mute.tap()
        XCTAssertEqual(mute.label,"Mute audio")
        XCTAssertEqual(mute.value as? String,"Sound on")
    }
    func testManualPauseStillSurvivesHomeWithoutEngineControls()throws {
        let app=try launch()
        app.buttons["Pause instrument"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout:10))
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(app.buttons["Resume instrument"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        XCTAssertFalse(element("SLOOP engine",in:app).exists)
        app.buttons["Resume instrument"].tap()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:15))
    }
}

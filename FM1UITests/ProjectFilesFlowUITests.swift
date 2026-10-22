import XCTest

/// Every writable project belongs to the supplied, isolated firmware fixture.
final class ProjectFilesFlowUITests:XCTestCase {
    private func element(_ id:String,in app:XCUIApplication)->XCUIElement {
        app.descendants(matching:.any).matching(identifier:id).firstMatch
    }
    private func launch()throws->XCUIApplication {
        guard let fixture=ProcessInfo.processInfo.environment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"] else {
            throw XCTSkip("Requires an isolated SLOOP fixture; never uses the normal app library")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchArguments += ["-instrumentHeaderCollapsed","NO"]
        app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture
        app.launch()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:30))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        return app
    }
    private func reveal(_ target:XCUIElement,in app:XCUIApplication) {
        let scroll=app.scrollViews.firstMatch
        for _ in 0..<14 {
            if target.exists && target.isHittable {return}
            scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.78)).press(forDuration:0.05,thenDragTo:scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.48)))
        }
        XCTAssertTrue(target.exists && target.isHittable,"The action must remain reachable in a landscape sheet")
    }
    private func capture(_ name:String) {
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
    func testSaveProjectCopyAndRenderWAVHaveRealFileReviews()throws {
        let app=try launch()
        element("Projects and files",in:app).tap()
        let sections=element("Project files section",in:app)
        XCTAssertTrue(sections.waitForExistence(timeout:10))
        let save=element("Save project copy",in:app)
        reveal(save,in:app);save.tap()
        let dialog=app.alerts["Save a copy"]
        XCTAssertTrue(dialog.waitForExistence(timeout:10))
        let marker="UI-\(UUID().uuidString.prefix(8))"
        let field=dialog.textFields.firstMatch
        field.tap();field.typeText(" "+marker)
        let name=try XCTUnwrap(field.value as? String)
        XCTAssertTrue(name.contains(marker),"The saved name must include the user’s unique input")
        dialog.buttons["Save"].tap()
        let savedName=app.staticTexts[name]
        XCTAssertTrue(savedName.waitForExistence(timeout:25))
        let menu=element("Actions for \(name)",in:app)
        capture("Saved work · compact library")
        reveal(menu,in:app);menu.tap()
        element("Open copy…",in:app).tap()
        let open=app.buttons["Back up and open"]
        XCTAssertTrue(open.waitForExistence(timeout:5),"Opening a copy must disclose replacement before applying it")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(savedName.exists,"Cancelling must keep the saved copy")
        menu.tap();element("Open copy…",in:app).tap()
        app.buttons["Back up and open"].tap()
        XCTAssertTrue(app.staticTexts["Project opened as a copy. Previous work is in a recovery backup."].waitForExistence(timeout:25))
        XCTAssertFalse(app.staticTexts["Recovery before replacement"].exists,"Recovery files should not crowd the named-copy library")
        reveal(menu,in:app);menu.tap()
        element("Export…",in:app).tap()
        let review=app.navigationBars["Review export"]
        XCTAssertTrue(review.waitForExistence(timeout:20))
        let namedExport=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@ AND label ENDSWITH %@",marker,".fm1project")).firstMatch
        XCTAssertTrue(namedExport.exists,"The actual export must preserve the user’s name, not use a UUID filename")
        XCTAssertTrue(element("Save prepared file",in:app).isEnabled)
        XCTAssertTrue(element("Share prepared file",in:app).isEnabled)
        capture("Named project · real export review")
        review.buttons["Done"].tap()
        XCTAssertTrue(sections.waitForExistence(timeout:10))
        sections.buttons["Samples"].tap()
        capture("Samples · import guidance")
        sections.buttons["Audio"].tap()
        let source=element("Audio export source",in:app)
        source.buttons["Whole song"].tap()
        XCTAssertFalse(element("Audio music duration",in:app).exists)
        capture("Whole song · complete arrangement export")
        source.buttons["Loop"].tap()
        capture("Audio · loop export")
        let duration=element("Audio music duration",in:app)
        reveal(duration,in:app);duration.tap()
        element("5 seconds",in:app).tap()
        let tail=element("Audio effect tail",in:app)
        reveal(tail,in:app);tail.tap();element("None",in:app).tap()
        let render=element("Export WAV",in:app)
        reveal(render,in:app);render.tap()
        XCTAssertTrue(review.waitForExistence(timeout:90),"Rendering must finish with an actual prepared WAV or expose its error")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(element("SLOOP-performance.wav",in:app).exists)
        XCTAssertTrue(element("Stereo audio mix · 44.1 kHz · 16-bit PCM WAV",in:app).exists)
        let files=element("Save prepared file",in:app),share=element("Share prepared file",in:app)
        reveal(files,in:app);XCTAssertTrue(files.isEnabled)
        reveal(share,in:app);XCTAssertTrue(share.isEnabled)
        XCTAssertFalse(element("File delivery status",in:app).exists,"Preparing a file must not pretend a destination has saved it")
        capture("SLOOP WAV · actual prepared file")
        review.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Projects and files"].waitForExistence(timeout:10))
        app.navigationBars["Projects and files"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["Pause instrument"].exists)
    }
    func testFolderIsOnlyAvailableForSloop()throws {
        let app=try launch()
        for (name,supported) in [("SLOOP-2.8",true),("Felucca-1.6.1",false),("SLOOP-2.8",true)] {
            element("Firmware library",in:app).tap()
            let installed=element("Installed firmware \(name)",in:app)
            XCTAssertTrue(installed.waitForExistence(timeout:10));installed.tap()
            XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:30))
            let folder=element("Projects and files",in:app)
            let expected=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in folder.exists == supported},object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[expected],timeout:10),.completed)
        }
    }
    func testCaptureAllSixFinishFileSections()throws {
        guard ProcessInfo.processInfo.environment["FM1_CAPTURE_PROJECT_FINISHES"] == "1" else {
            throw XCTSkip("Opt-in six-finish captures; functional file flow runs separately")
        }
        let app=try launch(),picker=element("Panel color",in:app)
        let original=picker.value as? String ?? "Black"
        defer {
            if app.state == .runningForeground {
                if app.navigationBars["Projects and files"].exists {app.navigationBars["Projects and files"].buttons["Done"].tap()}
                if picker.isHittable {picker.tap();element("Finish \(original)",in:app).tap()}
            }
        }
        for finish in ["Black","Purple","Orange","Black-Green","Cool Gray","White-Blue"] {
            picker.tap();element("Finish \(finish)",in:app).tap()
            element("Projects and files",in:app).tap()
            let sections=element("Project files section",in:app)
            XCTAssertTrue(sections.waitForExistence(timeout:10))
            for title in ["Saved work","Samples","Audio"] {
                sections.buttons[title].tap()
                let settled=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in sections.isHittable && app.frame.width>app.frame.height},object:nil)
                XCTAssertEqual(XCTWaiter.wait(for:[settled],timeout:5),.completed)
                capture("Native files · \(finish) · \(title)")
            }
            app.navigationBars["Projects and files"].buttons["Done"].tap()
        }
        XCTAssertTrue(app.staticTexts["Playing"].exists)
    }
}

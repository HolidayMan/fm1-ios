import XCTest

/// Actual system Files/Share UI, with no app hooks or direct container reads.
/// Opt in only on a dedicated simulator with an isolated SLOOP directory and
/// a writable local Files Downloads folder. Never run against an owner library.
final class ProjectFilesDeliveryUITests:XCTestCase {
    override func setUpWithError()throws {continueAfterFailure=false}

    private func element(_ id:String,in app:XCUIApplication)->XCUIElement {
        app.descendants(matching:.any).matching(identifier:id).firstMatch
    }
    private func launchFixture()throws->XCUIApplication {
        let environment=ProcessInfo.processInfo.environment
        guard environment["FM1_FILES_DELIVERY_TEST"] == "1",
              let fixture=environment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"],
              fixture.hasPrefix("Documents/PerformanceFixtures/") else {
            throw XCTSkip("Opt in on a dedicated simulator with an isolated PerformanceFixtures/SLOOP library and Files Downloads")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchArguments += ["-instrumentHeaderCollapsed","NO"]
        app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture
        app.launch()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:30))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        element("Projects and files",in:app).tap()
        XCTAssertTrue(app.navigationBars["Projects and files"].waitForExistence(timeout:10))
        return app
    }
    private func reveal(_ target:XCUIElement,in app:XCUIApplication) {
        let scroll=app.scrollViews.firstMatch
        for _ in 0..<16 {
            if target.exists && target.isHittable {return}
            if target.exists && target.frame.minY < scroll.frame.minY {scroll.swipeDown()}
            else {scroll.swipeUp()}
        }
        XCTAssertTrue(target.exists && target.isHittable,"The file action must be reachable in landscape")
    }
    private func capture(_ name:String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    private func backups(_ app:XCUIApplication)->XCUIElement {
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Recovery & backups (")).firstMatch
    }
    private func backupCount(_ app:XCUIApplication)throws->Int {
        let control=backups(app)
        XCTAssertTrue(control.exists)
        let tail=try XCTUnwrap(control.label.split(separator:"(").last)
        return try XCTUnwrap(Int(tail.replacingOccurrences(of:")",with:"")))
    }
    /// Both exporters and importers remember their last location. The picker can
    /// therefore start in Downloads, Browse, Recents or the Locations list.
    private func chooseLocalDownloads(in app:XCUIApplication) {
        // iOS 27 attaches the remote Files hierarchy to the host after the app
        // becomes idle. Querying immediately sees only remote placeholders.
        let navigation=app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(navigation.waitForExistence(timeout:30),"Wait for the actual native Files hierarchy: \(app.debugDescription)")
        let browse=app.buttons["Browse"].firstMatch
        if browse.waitForExistence(timeout:3),browse.isHittable {browse.tap()}
        else {
            let back=app.buttons["DOC.navBarButton.backInHistory"]
            if back.exists,back.isHittable {back.tap()}
        }
        let local=app.staticTexts.matching(NSPredicate(format:"label == %@ OR label == %@","On My iPhone","On My iPad")).firstMatch
        if local.waitForExistence(timeout:5),local.isHittable {local.tap()}
        let downloads=app.cells["Downloads, Folder"].firstMatch
        if downloads.waitForExistence(timeout:10),downloads.isHittable {
            downloads.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).tap()
        }
        let downloadsRoot=app.otherElements["DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage, Title: Downloads"]
        if !downloadsRoot.waitForExistence(timeout:5),downloads.exists {
            downloads.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).doubleTap()
        }
        XCTAssertTrue(downloadsRoot.waitForExistence(timeout:8),"Choose local Files Downloads rather than an unrelated provider: \(app.debugDescription)")
    }
    private func nameExport(_ name:String,in app:XCUIApplication) {
        let field=app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:8),"The native export picker must expose its filename field: \(app.debugDescription)")
        field.tap()
        field.press(forDuration:1)
        let selectAll=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","Select All")).firstMatch
        if selectAll.waitForExistence(timeout:2),selectAll.isHittable {selectAll.tap()}
        else {
            // If the system initially selected the whole name, the first delete
            // clears it; otherwise consume the existing text before typing.
            let old=field.value as? String ?? ""
            field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.utf16.count))
        }
        field.typeText(name)
        XCTAssertEqual(field.value as? String,name,"Use a new synthetic filename so no replacement of existing Files content is needed")
    }
    private func closeShareWithoutDelivery(in app:XCUIApplication) {
        let close=app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Close","Cancel")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout:10),"The real system activity sheet must offer dismissal: \(app.debugDescription)")
        capture("System Share · backup prepared, no destination selected")
        close.tap()
        XCTAssertTrue(app.navigationBars["Review export"].waitForExistence(timeout:10))
        XCTAssertTrue(element("Save prepared file",in:app).isHittable)
        XCTAssertFalse(element("File delivery status",in:app).exists,"Cancelling Share must not claim that any activity received the file")
    }
    func testBackupDeliveredToFilesReimportsAndShareCancellationKeepsReview()throws {
        let app=try launchFixture()
        let group=backups(app)
        reveal(group,in:app);group.tap()
        let save=element("Export backup",in:app)
        reveal(save,in:app);save.tap()
        let review=app.navigationBars["Review export"]
        XCTAssertTrue(review.waitForExistence(timeout:30))
        XCTAssertTrue(app.staticTexts["SLOOP workspace backup.fm1backup"].exists)
        XCTAssertFalse(element("File delivery status",in:app).exists,"Preparation is not delivery")

        let share=element("Share prepared file",in:app)
        reveal(share,in:app);share.tap()
        closeShareWithoutDelivery(in:app)

        let fileName="PocketFM-Delivery-\(UUID().uuidString.prefix(8))"
        let saveToFiles=element("Save prepared file",in:app)
        reveal(saveToFiles,in:app);saveToFiles.tap()
        chooseLocalDownloads(in:app)
        nameExport(fileName,in:app)
        let systemSave=app.buttons["Save"].firstMatch
        XCTAssertTrue(systemSave.isEnabled);systemSave.tap()
        let saved=element("File delivery status",in:app)
        XCTAssertTrue(saved.waitForExistence(timeout:20))
        XCTAssertEqual(saved.label,"Saved to the destination you selected.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("Backup · actual Files destination confirmed")
        review.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Projects and files"].waitForExistence(timeout:10))

        // Cancelling the external document provider must not create an imported
        // library copy or a recovery backup, nor replace the current workspace.
        let count=try backupCount(app)
        let previousStatus=element("File action status",in:app).label
        let importAction=element("Import project",in:app)
        reveal(importAction,in:app);importAction.tap()
        let pickerNavigation=app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(pickerNavigation.waitForExistence(timeout:30))
        let cancel=pickerNavigation.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout:10));cancel.tap()
        XCTAssertTrue(app.navigationBars["Projects and files"].waitForExistence(timeout:10))
        XCTAssertFalse(app.navigationBars["Review backup"].exists)
        XCTAssertEqual(try backupCount(app),count)
        XCTAssertEqual(element("File action status",in:app).label,previousStatus)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        reveal(importAction,in:app);importAction.tap()
        chooseLocalDownloads(in:app)
        let file=app.cells.matching(NSPredicate(format:"label BEGINSWITH %@",fileName)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout:12),"The backup just saved through Files must be selectable with the app’s declared document type: \(app.debugDescription)")
        XCTAssertTrue(file.isHittable);file.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).tap()
        let importReview=app.navigationBars["Review backup"]
        XCTAssertTrue(importReview.waitForExistence(timeout:20),"A real external .fm1backup must validate before confirmation")
        XCTAssertTrue(app.staticTexts["SLOOP workspace backup"].exists)
        capture("External Files backup · validated import review")
        let confirm=element("Confirm project import",in:app)
        reveal(confirm,in:app);XCTAssertTrue(confirm.isEnabled);confirm.tap()
        let imported=app.staticTexts["Imported as a new local copy. Previous work is backed up."]
        XCTAssertTrue(imported.waitForExistence(timeout:30))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertEqual(try backupCount(app),count+2,"Import must retain a named backup copy and a pre-replacement recovery")
        capture("External backup · imported with recovery")
        app.navigationBars["Projects and files"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["Pause instrument"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}

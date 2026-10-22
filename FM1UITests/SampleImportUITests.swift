import XCTest

/// Exercises the system document picker with a separately seeded, synthetic recording.
/// Run only on a dedicated simulator with an isolated firmware directory.
final class SampleImportUITests:XCTestCase {
    private func element(_ id:String,in app:XCUIApplication)->XCUIElement {
        // SwiftUI's outer graph identifier is inherited by the two adjustable
        // children. Their observed, user-facing labels remain distinct.
        if id == "Sample trim start handle" {return app.otherElements.matching(NSPredicate(format:"label == %@","Sample start")).firstMatch}
        if id == "Sample trim end handle" {return app.otherElements.matching(NSPredicate(format:"label == %@","Sample end")).firstMatch}
        return app.descendants(matching:.any).matching(identifier:id).firstMatch
    }
    private func visibleScroll(in app:XCUIApplication)->XCUIElement {
        let scrolls=app.scrollViews.allElementsBoundByIndex
        return scrolls.last(where:{$0.isHittable}) ?? scrolls.last ?? app.scrollViews.firstMatch
    }
    private func reveal(_ target:XCUIElement,in app:XCUIApplication) {
        let scroll=visibleScroll(in:app)
        for _ in 0..<12 {
            if target.exists && target.isHittable {return}
            scroll.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.8)).press(forDuration:0.05,thenDragTo:scroll.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.43)))
        }
        XCTAssertTrue(target.exists && target.isHittable)
    }
    private func capture(_ name:String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    private func launchFixture()throws->(XCUIApplication,String) {
        continueAfterFailure=false
        let environment=ProcessInfo.processInfo.environment
        guard let fixture=environment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"],
              let name=environment["FM1_SAMPLE_IMPORT_FILENAME"] else {
            throw XCTSkip("Requires isolated firmware and a synthetic WAV seeded into Files Downloads")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchArguments += ["-instrumentHeaderCollapsed","NO"]
        app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture
        app.launch()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:30))
        return (app,name)
    }
    private func openEditor(_ app:XCUIApplication,name:String) {
        element("Projects and files",in:app).tap()
        let sections=element("Project files section",in:app)
        XCTAssertTrue(sections.waitForExistence(timeout:10));sections.buttons["Samples"].tap()
        let choose=element("Import sample",in:app)
        reveal(choose,in:app);choose.tap()
        // The picker is real UIDocumentPickerViewController, including its provider filters.
        let picker=app
        let navigation=app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(navigation.waitForExistence(timeout:30),"The system picker must expose its native navigation before querying its provider content")
        print("NATIVE_FILES_PICKER_AX\n"+app.debugDescription)
        let browse=picker.buttons["Browse"].firstMatch
        if browse.exists {browse.tap()}
        else {
            let back=picker.buttons["DOC.navBarButton.backInHistory"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout:10))
            back.tap()
        }
        print("NATIVE_FILES_LOCATION_AX\n"+app.debugDescription)
        let local=picker.staticTexts["On My iPhone"].firstMatch
        if local.waitForExistence(timeout:5) {local.tap()}
        let downloads=picker.cells["Downloads, Folder"].firstMatch
        if downloads.waitForExistence(timeout:10) {downloads.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).tap()}
        let file=picker.cells.matching(NSPredicate(format:"label BEGINSWITH %@",(name as NSString).deletingPathExtension)).firstMatch
        if !file.waitForExistence(timeout:5),downloads.exists {
            downloads.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).doubleTap()
        }
        XCTAssertTrue(file.waitForExistence(timeout:10),"Synthetic file must appear in the native audio picker: \(app.debugDescription)")
        file.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).tap()
        XCTAssertTrue(app.navigationBars["Trim sample"].waitForExistence(timeout:15),"Selecting a real URL must open the editor: \(app.debugDescription)")
        print("ACTUAL_SAMPLE_EDITOR_AX\n"+app.debugDescription)
        capture("Sample import · actual waveform editor")
    }
    func testRealAudioPickerPreviewTrimAndTrackAssignment()throws {
        let (app,name)=try launchFixture()
        openEditor(app,name:name)
        let zoom=element("Sample waveform zoom",in:app)
        reveal(zoom,in:app);zoom.tap() // Whole 120-second recording.
        let scroll=visibleScroll(in:app)
        let graphStart=app.otherElements.matching(NSPredicate(format:"label == %@","Sample start")).firstMatch
        XCTAssertTrue(graphStart.waitForExistence(timeout:10),"The native trim handle must be accessible: \(app.debugDescription)")
        // GeometryReader itself has no AX node. Use the observed accessible
        // handle's vertical center to touch the overview at 80% of its width.
        scroll.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:scroll.frame.width*0.8,dy:graphStart.frame.midY-scroll.frame.minY)).tap()
        reveal(zoom,in:app);zoom.tap() // Zoom around the later fixed-length window.
        let start=app.otherElements.matching(NSPredicate(format:"label == %@","Sample start")).firstMatch
        let end=app.otherElements.matching(NSPredicate(format:"label == %@","Sample end")).firstMatch
        XCTAssertTrue(start.exists);XCTAssertTrue(end.exists)
        let startSeconds=Double(((start.value as? String ?? "").components(separatedBy:" ").first ?? "").replacingOccurrences(of:",",with:".")) ?? -1
        XCTAssertGreaterThan(startSeconds,60,"Full-recording gesture must select a later region without expanding it beyond slot capacity")
        XCTAssertEqual(app.sliders.count,0,"Trimming uses one waveform and two handles")
        let region=element("Selected sample region",in:app)
        let before=region.label
        end.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.1,thenDragTo:end.coordinate(withNormalizedOffset:CGVector(dx:-1,dy:0.5)))
        XCTAssertNotEqual(region.label,before,"Dragging the end handle must change the selected region")
        let preview=element("Audition sample",in:app)
        reveal(preview,in:app);preview.tap()
        XCTAssertTrue(app.buttons["Stop preview"].waitForExistence(timeout:8),"Preview must enter actual AVAudioPlayer playback")
        capture("Sample import · one waveform and playing preview")
        preview.tap()
        XCTAssertTrue(app.buttons["Play preview"].waitForExistence(timeout:5))
        let tracks=element("Sample track",in:app)
        reveal(tracks,in:app);tracks.buttons["Track 3"].tap()
        let apply=element("Apply sample",in:app)
        reveal(apply,in:app);XCTAssertTrue(apply.isEnabled);apply.tap()
        let replace=app.buttons["Back up and replace"]
        XCTAssertTrue(replace.waitForExistence(timeout:5));replace.tap()
        XCTAssertTrue(app.navigationBars["Projects and files"].waitForExistence(timeout:30))
        let status=element("File action status",in:app)
        XCTAssertTrue(status.waitForExistence(timeout:10))
        XCTAssertTrue(status.label.contains("Track 3"),"Successful import must identify the assigned track: \(status.label)")
        capture("Sample import · USR1 assigned to Track 3")
        app.navigationBars["Projects and files"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:10),"Prior playback demand must resume after audition and import")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testPausedInstrumentPreviewCancelsWithoutResumingSynth()throws {
        let (app,name)=try launchFixture()
        app.buttons["Pause instrument"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout:10))
        openEditor(app,name:name)
        let preview=element("Audition sample",in:app)
        reveal(preview,in:app);preview.tap()
        XCTAssertTrue(app.buttons["Stop preview"].waitForExistence(timeout:8),"Paused synth must not prevent sample audition")
        capture("Paused instrument · active sample preview")
        app.navigationBars["Trim sample"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Projects and files"].waitForExistence(timeout:10))
        app.navigationBars["Projects and files"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["Resume instrument"].exists,"Cancelling audition must preserve manual pause")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

}

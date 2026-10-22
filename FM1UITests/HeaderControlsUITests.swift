import XCTest

final class HeaderControlsUITests:XCTestCase {
    // AX frame conversion can report44pt as43.999999999999986; allow only a0.001pt numeric tolerance.
    private func element(_ identifier:String,in app:XCUIApplication)->XCUIElement {
        app.descendants(matching:.any).matching(identifier:identifier).firstMatch
    }
    private func waitUntilHittable(_ control:XCUIElement) {
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in control.isHittable},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:5),.completed)
    }
    private func expanded(_ expanded:Bool,in app:XCUIApplication) {
        let toggle=element("Toggle top controls",in:app)
        XCTAssertTrue(toggle.waitForExistence(timeout:10))
        if toggle.value as? String != (expanded ? "Expanded" : "Collapsed") {
            // Real tap towards the outer, rounded corner, not AX activation.
            toggle.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.25)).tap()
        }
        XCTAssertEqual(toggle.value as? String,expanded ? "Expanded" : "Collapsed")
    }
    private func assertSideControl(in app:XCUIApplication) {
        let toggle=element("Toggle top controls",in:app)
        let settled=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in
            toggle.isHittable && toggle.frame.width>=44-0.001 && toggle.frame.height>=44-0.001 && app.frame.insetBy(dx:11,dy:11).contains(toggle.frame)
        },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[settled],timeout:5),.completed,"The side target must settle inside the window after rotation")
        XCTAssertTrue(toggle.isHittable)
        XCTAssertGreaterThanOrEqual(toggle.frame.width,44-0.001)
        XCTAssertGreaterThanOrEqual(toggle.frame.height,44-0.001)
        XCTAssertTrue(app.frame.insetBy(dx:11,dy:11).contains(toggle.frame),"The entire target must clear rounded screen edges by at least 12pt, allowing 1pt rounding")
        XCTAssertGreaterThanOrEqual(toggle.frame.minY,app.frame.minY+15,"Keep side icons below the top corner, allowing 1pt rounding")
        for identifier in ["Enlarge display","MASTER","KNOB4","F3","B5"] {
            let control=element(identifier,in:app)
            if control.exists {XCTAssertFalse(toggle.frame.intersects(control.frame),"The side toggle must not cover \(identifier)")}
        }
    }
    func testCollapseGrowsPanelAndDisplayAndPersistsWithoutHidingMenus() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments += ["--panel-touch-diagnostics"];app.launch()
        expanded(true,in:app)
        defer {if app.state == .runningForeground {expanded(true,in:app)}}
        for identifier in ["Firmware library","Mute audio","Panel color","About"] {
            let control=element(identifier,in:app)
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.height,44-0.001,"Compact appearance must retain the invisible touch height")
            XCTAssertGreaterThanOrEqual(control.frame.width,44-0.001)
            XCTAssertGreaterThanOrEqual(control.frame.minY,app.frame.minY-1)
            XCTAssertLessThanOrEqual(control.frame.maxX,app.frame.maxX)
            for name in ["Enlarge display","MASTER","KNOB4"] {
                let panelControl=element(name,in:app)
                if panelControl.exists {XCTAssertFalse(control.frame.intersects(panelControl.frame),"Compact transport targets must not cover \(name)")}
            }
        }
        let headerCapture=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        headerCapture.name="Compact spacing · expanded";headerCapture.lifetime = .keepAlways;add(headerCapture)
        let panel=element("Instrument panel",in:app), screen=element("Enlarge display",in:app)
        XCTAssertTrue(panel.waitForExistence(timeout:10));XCTAssertTrue(screen.exists)
        let expandedPanel=panel.frame,expandedScreen=screen.frame
        XCTAssertEqual(expandedPanel.minY-app.frame.minY,32,accuracy:1,"Compact header should reserve only32pt")
        let knobNames=["MASTER","SELECT","PRESETS","ALGORITHM","KNOB1","KNOB2","KNOB3","KNOB4"]
        let knobFrames=knobNames.map{element($0,in:app).frame}
        let knobSizes=knobFrames.map{ $0.size }
        let functionTop=element("FX",in:app).frame.minY
        let octaveTop=element("OCT−",in:app).frame.minY
        XCTAssertEqual(knobFrames[4].minY-panel.frame.minY-15,functionTop-knobFrames[4].maxY,accuracy:0.01,"Right row should be optically centered above the compact function grid")
        assertSideControl(in:app)
        expanded(false,in:app)
        for (name,size) in zip(knobNames,knobSizes) {
            let grown=element(name,in:app).frame
            XCTAssertEqual(grown.width,size.width,accuracy:0.01,"\(name) diameter must remain stable")
            XCTAssertEqual(grown.height,size.height,accuracy:0.01)
            XCTAssertFalse(grown.intersects(screen.frame))
        }
        let grownKnobs=knobNames.map{element($0,in:app).frame}
        let groupOffset=grownKnobs[2].minY-knobFrames[2].minY
        for i in 0..<4 {
            XCTAssertEqual(grownKnobs[i].minY-knobFrames[i].minY,groupOffset,accuracy:0.01,"All four left knobs must translate together")
        }
        XCTAssertEqual(grownKnobs[1].minX-grownKnobs[0].maxX,grownKnobs[2].minY-grownKnobs[0].maxY,accuracy:0.01)
        for i in 4..<8 {
            XCTAssertEqual(element("FX",in:app).frame.minY-grownKnobs[i].maxY,functionTop-knobFrames[i].maxY,accuracy:0.01,"Right knobs stay attached to the function keys")
            XCTAssertEqual(element("OCT−",in:app).frame.minY-grownKnobs[i].maxY,octaveTop-knobFrames[i].maxY,accuracy:0.01,"Right knobs follow the lower anchor, not the panel top")
        }
        let fullCapture=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        fullCapture.name="Anchored knobs · full instrument";fullCapture.lifetime = .keepAlways;add(fullCapture)
        XCTAssertFalse(element("Firmware library",in:app).exists)
        XCTAssertGreaterThan(panel.frame.height,expandedPanel.height+20)
        if app.frame.height<500 && app.frame.width>700 {
            XCTAssertGreaterThan(screen.frame.height,expandedScreen.height+1)
            XCTAssertGreaterThan(screen.frame.width,expandedScreen.width+1)
        } else {
            // Tablet and narrow window layouts can reach a horizontal LCD limit.
            XCTAssertGreaterThanOrEqual(screen.frame.height,expandedScreen.height)
            XCTAssertGreaterThanOrEqual(screen.frame.width,expandedScreen.width)
        }
        assertSideControl(in:app)
        app.terminate();app.launch()
        XCTAssertTrue(element("Toggle top controls",in:app).waitForExistence(timeout:10))
        XCTAssertEqual(element("Toggle top controls",in:app).value as? String,"Collapsed")
        assertSideControl(in:app)
        expanded(true,in:app)
        let color=element("Panel color",in:app)
        XCTAssertTrue(color.isHittable)
        // This falls in the target's bottom12pt over the panel's static top rim.
        color.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.88)).tap()
        XCTAssertTrue(element("Finish Black-Green",in:app).waitForExistence(timeout:10))
        element("Done",in:app).tap()
        waitUntilHittable(element("Firmware library",in:app))
        XCUIDevice.shared.orientation = .landscapeRight
        assertSideControl(in:app)
        expanded(false,in:app);assertSideControl(in:app)
        expanded(true,in:app)
    }
    func testCaptureSixFinishes()throws {
        guard ProcessInfo.processInfo.environment["FM1_CAPTURE_FINISHES"] == "1",
              let fixture=ProcessInfo.processInfo.environment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"] else {
            throw XCTSkip("Opt-in finish captures require an isolated firmware library")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture
        app.launch()
        expanded(true,in:app)
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:30))
        let originalFinish=element("Panel color",in:app).value as? String ?? "Black"
        defer {
            expanded(true,in:app)
            element("Panel color",in:app).tap()
            element("Finish \(originalFinish)",in:app).tap()
        }
        for finish in ["Black","Purple","Orange","Black-Green","Cool Gray","White-Blue"] {
            element("Panel color",in:app).tap()
            let option=element("Finish \(finish)",in:app)
            XCTAssertTrue(option.waitForExistence(timeout:10));option.tap()
            waitUntilHittable(element("Toggle top controls",in:app))
            let expandedCapture=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
            expandedCapture.name="\(finish) · expanded";expandedCapture.lifetime = .keepAlways;add(expandedCapture)
            expanded(false,in:app)
            let collapsedCapture=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
            collapsedCapture.name="\(finish) · collapsed";collapsedCapture.lifetime = .keepAlways;add(collapsedCapture)
            expanded(true,in:app)
        }
    }
    func testCollapsingControlsKeepsRunningAndPausedPlaybackChoices()throws {
        guard let fixture=ProcessInfo.processInfo.environment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"] else {
            throw XCTSkip("Playback verification requires an isolated firmware library")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture
        app.launch()
        expanded(true,in:app)
        defer {if app.state == .runningForeground {expanded(true,in:app)}}
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:30))
        expanded(false,in:app);expanded(true,in:app)
        XCTAssertTrue(app.buttons["Pause instrument"].exists)
        XCTAssertTrue(app.staticTexts["Playing"].exists)
        app.buttons["Pause instrument"].tap()
        XCTAssertTrue(app.buttons["Resume instrument"].waitForExistence(timeout:10))
        expanded(false,in:app);expanded(true,in:app)
        XCTAssertTrue(app.buttons["Resume instrument"].exists)
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}

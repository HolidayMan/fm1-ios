import XCTest
import UIKit
import CryptoKit

/// Destructive confirmation is exercised only in explicitly isolated fixtures.
/// The runner must seed pinned SLOOP + CoralFlower in the populated fixture and
/// create an empty second fixture. No product hooks or owner containers are used.
final class FirmwareResetUITests:XCTestCase {
    override func setUpWithError()throws {continueAfterFailure=false}

    private func element(_ id:String,in app:XCUIApplication)->XCUIElement {
        app.descendants(matching:.any).matching(identifier:id).firstMatch
    }
    private func wait(_ message:String,timeout:TimeInterval=30,_ predicate:@escaping()->Bool) {
        let expectation=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in predicate()},object:nil)
        let result=XCTWaiter.wait(for:[expectation],timeout:timeout)
        if result != .completed {capture("Reset · actual failure state")}
        XCTAssertEqual(result,.completed,message+(result == .completed ? "" : "\n"+XCUIApplication().debugDescription))
    }
    private func launch(empty:Bool=false)throws->XCUIApplication {
        let environment=ProcessInfo.processInfo.environment
        let key=empty ? "FM1_RESET_EMPTY_FIXTURE_DIRECTORY" : "FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"
        guard environment["FM1_RESET_UI"] == "1",let fixture=environment[key],
              fixture.hasPrefix("Documents/PerformanceFixtures/") else {
            throw XCTSkip("Requires explicit reset opt-in and dedicated isolated firmware fixtures")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture
        app.launch()
        expanded(true,in:app)
        XCTAssertTrue(element("Reset instrument",in:app).waitForExistence(timeout:15))
        if !empty {XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:30))}
        XCTAssertFalse(app.alerts.firstMatch.exists)
        return app
    }
    private func expanded(_ value:Bool,in app:XCUIApplication) {
        let toggle=element("Toggle top controls",in:app)
        XCTAssertTrue(toggle.waitForExistence(timeout:15))
        let expected=value ? "Expanded" : "Collapsed"
        if toggle.value as? String != expected {
            // Proven rounded-edge target used by HeaderControlsUITests. Do not
            // force the preference through launch arguments: that overrides the
            // UserDefaults value the collapse action needs to change.
            toggle.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.25)).tap()
        }
        wait("The header must become \(expected)",timeout:10) {toggle.value as? String == expected}
    }
    private func capture(_ name:String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    private func choose(_ name:String,in app:XCUIApplication) {
        element("Firmware library",in:app).tap()
        let search=app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:10));search.tap()
        if search.buttons["Clear text"].exists {search.buttons["Clear text"].tap()}
        else {
            let previous=search.value as? String ?? ""
            if !previous.isEmpty && previous != "Find a firmware" && previous != "Search" {
                search.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:previous.count))
            }
        }
        search.typeText(name+"\n")
        let installed=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","Installed firmware \(name)")).firstMatch
        XCTAssertTrue(installed.waitForExistence(timeout:10));installed.tap()
        wait("The isolated installed instrument must load: \(name)") {
            !app.navigationBars["Firmware library"].exists &&
            self.element("Firmware library",in:app).label.contains(name) &&
            app.staticTexts["Playing"].exists && self.element("Reset instrument",in:app).isEnabled
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    private func confirmation(in app:XCUIApplication)->XCUIElement {
        let reset=element("Reset instrument",in:app)
        XCTAssertTrue(reset.isEnabled && reset.isHittable);reset.tap()
        let alert=app.alerts["Reset current instrument?"]
        XCTAssertTrue(alert.waitForExistence(timeout:10))
        XCTAssertTrue(alert.buttons["Reset"].exists)
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","A recovery copy of saved data is kept.")).firstMatch.exists)
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Save unsaved edits inside the firmware first.")).firstMatch.exists)
        return alert
    }
    private func restoreConfirmation(in app:XCUIApplication)->XCUIElement {
        element("Reset instrument",in:app).press(forDuration:0.8)
        let restore=element("Restore pre-reset saved data…",in:app)
        // Native context menu actions expose their visible label, without a
        // product-specific test identifier.
        let action=restore.exists ? restore : app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","Restore pre-reset saved data…")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout:10));action.tap()
        let alert=app.alerts["Restore pre-reset saved data?"]
        XCTAssertTrue(alert.waitForExistence(timeout:10))
        XCTAssertTrue(alert.buttons["Restore"].exists)
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        return alert
    }
    private func pause(_ app:XCUIApplication) {
        app.buttons["Pause instrument"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["Resume instrument"].exists)
    }
    /// Compare decoded pixels, not PNG metadata or an animated full-panel frame.
    /// The source LCD is frozen while the main instrument is explicitly paused.
    private func lcdPixels(_ app:XCUIApplication)throws->Data {
        let display=element("Enlarge display",in:app)
        XCTAssertTrue(display.exists)
        let image=try XCTUnwrap(display.screenshot().image.cgImage)
        let width=image.width,height=image.height
        var rgba=[UInt8](repeating:0,count:width*height*4)
        try rgba.withUnsafeMutableBytes {buffer in
            let context=try XCTUnwrap(CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,
                bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image,in:CGRect(x:0,y:0,width:CGFloat(width),height:CGFloat(height)))
        }
        var colors=Set<UInt32>()
        for y in stride(from:8,to:max(9,height-8),by:4) {
            for x in stride(from:8,to:max(9,width-8),by:4) {
                let i=(y*width+x)*4
                colors.insert(UInt32(rgba[i])<<16 | UInt32(rgba[i+1])<<8 | UInt32(rgba[i+2]))
            }
        }
        XCTAssertGreaterThan(colors.count,4,"The actual native LCD must show firmware content; a fresh paused splash has a small palette")
        return Data(rgba)
    }
    private func frames(_ app:XCUIApplication)->[String:CGRect] {
        Dictionary(uniqueKeysWithValues:["F3","C4","C5","G5","FX","HOME","MASTER","KNOB4"].map{($0,element($0,in:app).frame)})
    }
    private func assertFrames(_ expected:[String:CGRect],in app:XCUIApplication) {
        for (id,before) in expected {
            let after=element(id,in:app).frame
            XCTAssertEqual(after.minX,before.minX,accuracy:0.01,id)
            XCTAssertEqual(after.minY,before.minY,accuracy:0.01,id)
            XCTAssertEqual(after.width,before.width,accuracy:0.01,id)
            XCTAssertEqual(after.height,before.height,accuracy:0.01,id)
        }
    }
    func testResetHeaderTargetEmptyDisabledAndCollapseKeepsCompactLayout()throws {
        let app=try launch(empty:true)
        let reset=element("Reset instrument",in:app),panel=element("Instrument panel",in:app)
        XCTAssertFalse(reset.isEnabled,"No current instrument means there is nothing to reset")
        XCTAssertGreaterThanOrEqual(reset.frame.width,44-0.001)
        XCTAssertGreaterThanOrEqual(reset.frame.height,44-0.001)
        XCTAssertEqual(panel.frame.minY-app.frame.minY,32,accuracy:1)
        let expandedPanel=panel.frame
        expanded(false,in:app)
        wait("Collapsing the header removes its controls") {!reset.exists}
        XCTAssertEqual(element("Toggle top controls",in:app).value as? String,"Collapsed")
        XCTAssertGreaterThan(panel.frame.height,expandedPanel.height+20)
        XCTAssertEqual(panel.frame.minY-app.frame.minY,0,accuracy:1)
        capture("Reset · collapsed header keeps full panel")
        expanded(true,in:app)
        XCTAssertTrue(reset.waitForExistence(timeout:10));XCTAssertFalse(reset.isEnabled)
        XCTAssertEqual(panel.frame.minY,expandedPanel.minY,accuracy:1)
        capture("Reset · empty instrument disabled with compact header")
    }
    func testPausedCoralCancelPreservesPixelsAndConfirmedResetStaysPaused()throws {
        let app=try launch();choose("CoralFlower",in:app)
        let reset=element("Reset instrument",in:app)
        XCTAssertTrue(reset.isHittable && reset.isEnabled)
        XCTAssertGreaterThanOrEqual(reset.frame.width,44-0.001)
        XCTAssertGreaterThanOrEqual(reset.frame.height,44-0.001)
        XCTAssertFalse(reset.frame.intersects(element("Enlarge display",in:app).frame))
        let geometry=frames(app),selected=element("Firmware library",in:app).label
        app.buttons["OCT+"].tap()
        app.buttons["C4"].press(forDuration:1.2)
        pause(app)
        let edited=try lcdPixels(app)
        let alert=confirmation(in:app)
        capture("Reset · explicit scope and recovery confirmation")
        alert.buttons["Cancel"].tap()
        wait("Cancel returns to the unchanged paused instrument") {!app.alerts.firstMatch.exists && reset.isHittable}
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        XCTAssertEqual(element("Firmware library",in:app).label,selected)
        XCTAssertEqual(SHA256.hash(data:try lcdPixels(app)),SHA256.hash(data:edited),"Cancel must leave the frozen firmware LCD unchanged")
        assertFrames(geometry,in:app)
        confirmation(in:app).buttons["Reset"].tap()
        // A busy state may be too short to observe; if displayed, the new reset
        // button must be disabled. The durable busy guard is unit-tested too.
        if app.staticTexts["Loading…"].exists {XCTAssertFalse(reset.isEnabled)}
        wait("Reset settles without changing the explicit paused choice") {
            !app.alerts.firstMatch.exists && reset.isEnabled && app.staticTexts["Paused"].exists
        }
        XCTAssertEqual(element("Firmware library",in:app).label,selected)
        let fresh=try lcdPixels(app)
        XCTAssertNotEqual(SHA256.hash(data:fresh),SHA256.hash(data:edited),"The edited current instrument must be replaced with its fresh initial display")
        assertFrames(geometry,in:app)
        capture("Reset · CoralFlower fresh and still paused")
        let restore=restoreConfirmation(in:app)
        capture("Reset · explicit saved-data recovery confirmation")
        restore.buttons["Cancel"].tap()
        wait("Recovery cancellation retains the fresh paused instrument") {!app.alerts.firstMatch.exists && reset.isHittable}
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        XCTAssertEqual(SHA256.hash(data:try lcdPixels(app)),SHA256.hash(data:fresh))
        restoreConfirmation(in:app).buttons["Restore"].tap()
        wait("Restoring saved data preserves the explicit paused choice") {
            !app.alerts.firstMatch.exists && reset.isEnabled && app.staticTexts["Paused"].exists
        }
        XCTAssertEqual(element("Firmware library",in:app).label,selected)
        // The plant is volatile, so a power-on of the restored saved settings
        // need not reproduce its old animation pixels. Backend tests verify the
        // saved octave, slots and original raw-store recovery semantically.
        _=try lcdPixels(app);assertFrames(geometry,in:app)
        capture("Reset · CoralFlower saved data restored while paused")
        reset.press(forDuration:0.8)
        XCTAssertFalse(app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","Restore pre-reset saved data…")).firstMatch.exists,"Successful restore consumes the recovery action")
        // A platform with no remaining context actions may treat the long press
        // as the normal button action. Dismiss its confirmation without reset.
        if app.alerts["Reset current instrument?"].exists {
            app.alerts["Reset current instrument?"].buttons["Cancel"].tap()
        } else if app.staticTexts["Paused"].exists {
            app.staticTexts["Paused"].tap() // Dismiss an empty native context preview, if presented.
        }
        app.buttons["Resume instrument"].tap()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:15))
        app.buttons["C4"].press(forDuration:0.4)
        _=try lcdPixels(app)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("Reset · CoralFlower can play after resume")
    }
    func testRunningSloopResetKeepsSelectionPlaybackAndOtherInstrumentsUsable()throws {
        let app=try launch();choose("SLOOP",in:app)
        let selected=element("Firmware library",in:app).label
        let geometry=frames(app)
        confirmation(in:app).buttons["Reset"].tap()
        wait("A running reset must return to the same playing instrument") {
            !app.alerts.firstMatch.exists && self.element("Reset instrument",in:app).isEnabled && app.staticTexts["Playing"].exists
        }
        XCTAssertEqual(element("Firmware library",in:app).label,selected)
        _=try lcdPixels(app);assertFrames(geometry,in:app)
        app.buttons["C4"].press(forDuration:0.4)
        capture("Reset · SLOOP returns to Playing")
        choose("CoralFlower",in:app)
        app.buttons["C4"].press(forDuration:0.3)
        _=try lcdPixels(app)
        choose("SLOOP",in:app)
        XCTAssertEqual(element("Firmware library",in:app).label,selected)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}

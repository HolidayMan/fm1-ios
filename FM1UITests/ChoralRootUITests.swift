import XCTest
import UIKit
import CryptoKit

/// Explicit network opt-in, fresh app-private fixture, and actual public controls.
final class ChoralRootUITests:XCTestCase {
    override func setUpWithError()throws {continueAfterFailure=false}
    private func element(_ id:String,in app:XCUIApplication)->XCUIElement {
        app.descendants(matching:.any).matching(identifier:id).firstMatch
    }
    private func capture(_ name:String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    private func wait(_ message:String,timeout:TimeInterval=30,_ ready:@escaping()->Bool) {
        let expectation=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in ready()},object:nil)
        let result=XCTWaiter.wait(for:[expectation],timeout:timeout)
        if result != .completed {capture("ChoralRoot · actual failure state")}
        XCTAssertEqual(result,.completed,message+(result == .completed ? "" : "\n"+XCUIApplication().debugDescription))
    }
    private func library(_ name:String,in app:XCUIApplication) {
        element("Firmware library",in:app).tap()
        let search=app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:10));search.tap()
        if search.buttons["Clear text"].exists {search.buttons["Clear text"].tap()}
        else {
            let old=search.value as? String ?? ""
            if !old.isEmpty && old != "Find a firmware" && old != "Search" {search.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count))}
        }
        search.typeText(name+"\n")
    }
    private func selected(_ name:String,in app:XCUIApplication) {
        wait("The exact native release must play: \(name)",timeout:90) {
            !app.navigationBars["Firmware library"].exists &&
            self.element("Firmware library",in:app).label.contains(name) &&
            app.staticTexts["Playing"].exists && self.element("Reset instrument",in:app).isEnabled
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.buttons["Projects and files"].exists,"SLOOP-only file actions must remain hidden")
    }
    private func install(_ name:String,in app:XCUIApplication) {
        library(name,in:app)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","Installed firmware \(name)")).firstMatch.exists,"This path must actually download, using a fresh isolated fixture")
        let download=app.buttons["Download \(name)"]
        XCTAssertTrue(download.waitForExistence(timeout:10))
        if name == "ChoralRoot" {
            XCTAssertTrue(element("Download size choralroot",in:app).exists)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@","CZ-1","Prophet-5","INIT")).firstMatch.exists)
            capture("ChoralRoot · exact release and INIT limits")
        }
        XCTAssertTrue(download.isHittable);download.tap();selected(name,in:app)
    }
    private func choose(_ name:String,in app:XCUIApplication) {
        library(name,in:app)
        let installed=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","Installed firmware \(name)")).firstMatch
        XCTAssertTrue(installed.waitForExistence(timeout:10));installed.tap();selected(name,in:app)
    }
    private func lcd(_ app:XCUIApplication)throws->Data {
        let display=element("Enlarge display",in:app)
        let image=try XCTUnwrap(display.screenshot().image.cgImage),width=image.width,height=image.height
        var pixels=[UInt8](repeating:0,count:width*height*4)
        try pixels.withUnsafeMutableBytes {buffer in
            let context=try XCTUnwrap(CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image,in:CGRect(x:0,y:0,width:CGFloat(width),height:CGFloat(height)))
        }
        var colors=Set<UInt32>()
        for y in stride(from:8,to:max(9,height-8),by:4) {
            for x in stride(from:8,to:max(9,width-8),by:4) {let i=(y*width+x)*4;colors.insert(UInt32(pixels[i])<<16 | UInt32(pixels[i+1])<<8 | UInt32(pixels[i+2]))}
        }
        XCTAssertGreaterThan(colors.count,4,"The real native LCD must contain firmware content")
        return Data(pixels)
    }
    private func resetConfirmation(_ app:XCUIApplication)->XCUIElement {
        element("Reset instrument",in:app).tap()
        let alert=app.alerts["Reset current instrument?"]
        XCTAssertTrue(alert.waitForExistence(timeout:10));return alert
    }
    private func restoreConfirmation(_ app:XCUIApplication)->XCUIElement {
        element("Reset instrument",in:app).press(forDuration:0.8)
        let action=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","Restore pre-reset saved data…")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout:10));action.tap()
        let alert=app.alerts["Restore pre-reset saved data?"]
        XCTAssertTrue(alert.waitForExistence(timeout:10));return alert
    }
    func testActualDownloadMajorChordSavedDataRecoverySwitchAndRelaunch()throws {
        let env=ProcessInfo.processInfo.environment
        guard env["FM1_CHORALROOT_UI"] == "1",let fixture=env["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"],fixture.hasPrefix("Documents/PerformanceFixtures/Choral31") else {
            throw XCTSkip("Requires an explicitly opted-in fresh Choral31 simulator workspace; never uses owner files")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture;app.launch()
        let toggle=element("Toggle top controls",in:app)
        XCTAssertTrue(toggle.waitForExistence(timeout:15))
        if toggle.value as? String != "Expanded" {toggle.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.25)).tap()}
        wait("Expanded header must expose the real instrument controls") {toggle.value as? String == "Expanded"}
        install("ChoralRoot",in:app)
        XCTAssertTrue(element("Firmware library",in:app).label.contains("0.27"))
        _=try lcd(app)
        // Default LOCK is off. Its intended latch makes an Orchid-style chord
        // playable with one finger; MAJ is physical A#3, root is D4.
        XCTAssertTrue(app.buttons["LFO"].exists);XCTAssertTrue(app.buttons["A sharp3"].exists)
        app.buttons["LFO"].tap();app.buttons["A sharp3"].tap();app.buttons["D4"].press(forDuration:1)
        capture("ChoralRoot · latched MAJ and D root on native LCD")
        _=try lcd(app)
        app.buttons["OCT+"].tap();app.buttons["SAVE"].press(forDuration:1.8)
        app.buttons["Pause instrument"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout:15))
        let saved=try lcd(app),selection=element("Firmware library",in:app).label
        resetConfirmation(app).buttons["Cancel"].tap()
        wait("Reset cancellation keeps the selected paused ChoralRoot") {!app.alerts.firstMatch.exists && app.staticTexts["Paused"].exists}
        XCTAssertEqual(SHA256.hash(data:try lcd(app)),SHA256.hash(data:saved))
        resetConfirmation(app).buttons["Reset"].tap()
        wait("Reset must finish with the same selected instrument still paused") {!app.alerts.firstMatch.exists && self.element("Reset instrument",in:app).isEnabled && app.staticTexts["Paused"].exists}
        XCTAssertEqual(element("Firmware library",in:app).label,selection)
        let fresh=try lcd(app)
        XCTAssertNotEqual(SHA256.hash(data:fresh),SHA256.hash(data:saved))
        capture("ChoralRoot · fresh INIT instrument remains paused")
        restoreConfirmation(app).buttons["Cancel"].tap()
        wait("Recovery cancellation keeps the fresh paused instrument") {!app.alerts.firstMatch.exists && app.staticTexts["Paused"].exists}
        XCTAssertEqual(SHA256.hash(data:try lcd(app)),SHA256.hash(data:fresh))
        let restore=restoreConfirmation(app);capture("ChoralRoot · saved-data recovery confirmation")
        restore.buttons["Restore"].tap()
        wait("Saved-data recovery must keep ChoralRoot selected and paused") {!app.alerts.firstMatch.exists && self.element("Reset instrument",in:app).isEnabled && app.staticTexts["Paused"].exists}
        XCTAssertEqual(element("Firmware library",in:app).label,selection)
        _=try lcd(app);capture("ChoralRoot · saved sound restored")
        app.buttons["Resume instrument"].tap()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout:15));app.buttons["D4"].press(forDuration:0.5)
        install("CoralFlower",in:app);app.buttons["C4"].press(forDuration:0.3)
        choose("ChoralRoot",in:app)
        XCTAssertEqual(element("Firmware library",in:app).label,selection)
        _=try lcd(app);capture("ChoralRoot · separate release reopens after CoralFlower")
        app.terminate();app.launch()
        // Isolated lifecycle fixtures intentionally use a new preferences suite
        // each launch. Re-select the installed release to prove its on-disk
        // workspace reopens; ordinary remembered selection is tested separately.
        choose("ChoralRoot",in:app);app.buttons["D4"].press(forDuration:0.4)
        _=try lcd(app);capture("ChoralRoot · installed native workspace after relaunch")
    }
}

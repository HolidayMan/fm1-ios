import XCTest
import UIKit

final class ProjectFilesUITests:XCTestCase {
    // AX frame conversion can report44pt as43.999999999999986; allow only a0.001pt numeric tolerance.
    private func element(_ id:String,in app:XCUIApplication)->XCUIElement {
        app.descendants(matching:.any).matching(identifier:id).firstMatch
    }
    private func launch()throws->XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        if let fixture=ProcessInfo.processInfo.environment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"] {
            app.launchEnvironment["FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"]=fixture
        } else {throw XCTSkip("File UI requires an isolated native SLOOP fixture; no folder is shown without a supported engine")}
        app.launch();return app
    }
    func testFilesRemainAccessibleWithHeaderCollapsedAndDoNotCoverKeys()throws {
        let app=try launch(),toggle=element("Toggle top controls",in:app)
        XCTAssertTrue(toggle.waitForExistence(timeout:15))
        if toggle.value as? String == "Expanded" {toggle.tap()}
        defer {if app.state == .runningForeground, toggle.exists,toggle.value as? String == "Collapsed" {toggle.tap()}}
        let folder=element("Projects and files",in:app)
        for orientation in [UIDeviceOrientation.landscapeLeft,.landscapeRight] {
            XCUIDevice.shared.orientation=orientation
            let settled=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in
                folder.isHittable && toggle.isHittable && app.frame.width>app.frame.height && app.frame.insetBy(dx:11,dy:11).contains(folder.frame) && app.frame.insetBy(dx:11,dy:11).contains(toggle.frame)
            },object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[settled],timeout:5),.completed,"Both side targets must settle away from rounded corners after rotation")
            XCTAssertGreaterThanOrEqual(folder.frame.width,44-0.001);XCTAssertGreaterThanOrEqual(folder.frame.height,44-0.001)
            XCTAssertGreaterThanOrEqual(folder.frame.minY,toggle.frame.maxY+1)
            for name in ["MASTER","KNOB4","F3","B5","Enlarge display"] {
                let control=element(name,in:app)
                if control.exists {XCTAssertFalse(folder.frame.intersects(control.frame),"Files entry must not cover \(name)")}
            }
            let capture=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
            capture.name="Compact chrome · collapsed · \(orientation == .landscapeLeft ? "left" : "right")";capture.lifetime = .keepAlways;add(capture)
            folder.tap()
            XCTAssertTrue(element("Project files section",in:app).waitForExistence(timeout:10))
            app.buttons["Done"].firstMatch.tap()
            XCTAssertTrue(folder.waitForExistence(timeout:10))
            XCTAssertEqual(toggle.value as? String,"Collapsed","Opening files must not restore the transport row")
        }
    }
    func testFilesSectionsAndFinishAppearance()throws {
        let app=try launch(),toggle=element("Toggle top controls",in:app)
        XCTAssertTrue(toggle.waitForExistence(timeout:15))
        if toggle.value as? String == "Collapsed" {toggle.tap()}
        let picker=element("Panel color",in:app)
        XCTAssertTrue(picker.exists)
        let original=picker.value as? String ?? "Black"
        defer {
            if app.state == .runningForeground {
                if app.buttons["Done"].firstMatch.exists {app.buttons["Done"].firstMatch.tap()}
                if picker.isHittable {picker.tap();element("Finish \(original)",in:app).tap()}
            }
        }
        for finish in ["Orange","Purple","White-Blue"] {
            picker.tap();element("Finish \(finish)",in:app).tap()
            element("Projects and files",in:app).tap()
            let sections=element("Project files section",in:app)
            XCTAssertTrue(sections.waitForExistence(timeout:10))
            for title in ["Saved work","Samples","Audio"] {
                sections.buttons[title].tap()
                let capture=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
                capture.name="Files · \(finish) · \(title)";capture.lifetime = .keepAlways;add(capture)
            }
            app.buttons["Done"].firstMatch.tap()
        }
    }
}

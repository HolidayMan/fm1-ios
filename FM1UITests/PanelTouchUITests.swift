import XCTest

/// Real synthesized HID input traverses UIKit callbacks; no accessibilityActivate.
final class PanelTouchUITests:XCTestCase {
    private func receipt(_ key:XCUIElement)->[String:Int] {
        let text=key.value as? String ?? ""
        return Dictionary(uniqueKeysWithValues:text.split(separator:";").compactMap {item in
            let pair=item.split(separator:"=")
            guard pair.count==2,let value=Int(pair[1]) else{return nil}
            return (String(pair[0]),value)
        })
    }
    private func app()->XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments += ["--panel-touch-diagnostics","-instrumentHeaderCollapsed","NO"];app.launch()
        XCTAssertTrue(app.buttons["F3"].waitForExistence(timeout:10))
        return app
    }
    func testBothRowsRepeatedTapsAndBottomEdgeBeganWithoutGestureDelay() {
        let app=app()
        for name in ["F3","F sharp3"] {
            let key=app.buttons[name]
            key.tap(withNumberOfTaps:8,numberOfTouches:1)
            let r=receipt(key)
            print("TOUCH RECEIPT \(name): \(r)")
            XCTAssertEqual(r["began"],8,"Actual UIKit touch beginnings: \(name) \(r)")
            XCTAssertEqual(r["ended"],8);XCTAssertEqual(r["cancelled"],0)
            XCTAssertEqual(r["downs"],8);XCTAssertEqual(r["ups"],8);XCTAssertEqual(r["held"],0)
        }
        let bottom=app.buttons["F3"]
        let edge=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:bottom.frame.midX-app.frame.minX,dy:app.frame.height-1))
        edge.press(forDuration:0.25)
        let r=receipt(bottom)
        print("BOTTOM EDGE TOUCH RECEIPT: \(r)")
        XCTAssertEqual(r["began"],9,"Bottom casing touch must reach UIKit: \(r)")
        XCTAssertEqual(r["downs"],9);XCTAssertEqual(r["ups"],9);XCTAssertEqual(r["held"],0)
        XCTAssertLessThan(r["maxBeganDelayMs"] ?? Int.max,120,"Bottom edge must respond before the 250ms hold ends: \(r)")
        XCTAssertTrue(app.buttons["Firmware library"].exists,"Edge input must keep the instrument on screen")
    }
    func testTwoFingerSameKeyAndKeyboardSlideReleaseEveryKey() {
        let app=app(),key=app.buttons["C4"]
        key.twoFingerTap()
        var r=receipt(key)
        XCTAssertEqual(r["began"],2,"Two actual touches must reach the same key: \(r)")
        XCTAssertEqual(r["ended"],2);XCTAssertEqual(r["cancelled"],0)
        XCTAssertEqual(r["peakTouches"],2);XCTAssertEqual(r["downs"],1);XCTAssertEqual(r["ups"],1)
        XCTAssertEqual(r["held"],0)
        key.press(forDuration:0.05,thenDragTo:app.buttons["D4"])
        r=receipt(key)
        XCTAssertEqual(r["downs"],2);XCTAssertEqual(r["ups"],2);XCTAssertEqual(r["held"],0)
        let next=receipt(app.buttons["D4"])
        XCTAssertEqual(next["downs"],next["ups"]);XCTAssertEqual(next["held"],0)
        XCTAssertGreaterThan(next["downs"] ?? 0,0,"Slide must enter its destination key")
    }
}

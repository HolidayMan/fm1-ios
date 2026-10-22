import XCTest
import UIKit
@testable import FM1

final class ControlFeedbackTests:XCTestCase {
    func testDragRequiresFourPointsAndKeepsFractionalRemainder() {
        let small=KnobDrag.update(anchorY:100,currentY:96.1)
        XCTAssertEqual(small.steps,0);XCTAssertEqual(small.anchorY,100)
        let first=KnobDrag.update(anchorY:small.anchorY,currentY:95)
        XCTAssertEqual(first.steps,1);XCTAssertEqual(first.anchorY,96)
        let remainder=KnobDrag.update(anchorY:first.anchorY,currentY:92.1)
        XCTAssertEqual(remainder.steps,0);XCTAssertEqual(remainder.anchorY,96)
        let second=KnobDrag.update(anchorY:remainder.anchorY,currentY:92)
        XCTAssertEqual(second.steps,1);XCTAssertEqual(second.anchorY,92)
    }
    func testReversalConsumesOnlyNetMovementAndLargeDragKeepsRemainder() {
        let up=KnobDrag.update(anchorY:100,currentY:95)
        let reversing=KnobDrag.update(anchorY:up.anchorY,currentY:99.9)
        XCTAssertEqual(reversing.steps,0);XCTAssertEqual(reversing.anchorY,96)
        let down=KnobDrag.update(anchorY:reversing.anchorY,currentY:100)
        XCTAssertEqual(down.steps,-1);XCTAssertEqual(down.anchorY,100)
        let fast=KnobDrag.update(anchorY:100,currentY:79)
        XCTAssertEqual(fast.steps,5);XCTAssertEqual(fast.anchorY,80)
        let reverse=KnobDrag.update(anchorY:fast.anchorY,currentY:83.9)
        XCTAssertEqual(reverse.steps,0);XCTAssertEqual(reverse.anchorY,80)
    }
    func testSharedGateCoalescesChordAndDetentBursts() {
        var gate=HapticRateGate()
        let accepted=[0.0,0.001,0.002,0.049,0.050,0.051,0.101].filter {gate.allow(at:$0)}
        XCTAssertEqual(accepted,[0,0.05,0.101])
    }
    @MainActor func testPreparationDoesNotConsumePulseAndBothOutputsShareBurstCap() {
        var time=0.0,buttons=0,detents=0,prepared=0
        let feedback=ControlHaptics(button:{buttons += 1},detent:{detents += 1},prepareButton:{prepared += 1},now:{time})
        feedback.prepareButton();feedback.button()
        XCTAssertEqual(prepared,1);XCTAssertEqual(buttons,1)
        time=0.02;feedback.button();feedback.detent()
        XCTAssertEqual(buttons,1);XCTAssertEqual(detents,0)
        time=0.05;feedback.detent()
        time=0.06;feedback.prepareButton();feedback.button()
        XCTAssertEqual(prepared,2);XCTAssertEqual(buttons,1);XCTAssertEqual(detents,1)
        time=0.101;feedback.button();XCTAssertEqual(buttons,2)
    }
    @MainActor func testPanelEmitsOnlyNewKeyDownAndNeverReleaseOrDrawing() throws {
        var time=0.0,buttons=0
        let panel=HardwarePanel(frame:CGRect(x:0,y:0,width:774,height:355))
        panel.haptics=ControlHaptics(button:{buttons += 1},detent:{},now:{time})
        panel.layoutIfNeeded()
        let key=try XCTUnwrap((panel.accessibilityElements as? [UIAccessibilityElement])?.first{$0.accessibilityLabel == "F3"})
        XCTAssertTrue(key.accessibilityActivate());XCTAssertEqual(buttons,1)
        time=0.1
        XCTAssertTrue(key.accessibilityActivate());XCTAssertEqual(buttons,1,"Already-held key must not emit again")
        let released=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in key.accessibilityValue == "Released"},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[released],timeout:2),.completed)
        XCTAssertEqual(buttons,1,"Release must not emit feedback")
        panel.refreshDisplay()
        _ = UIGraphicsImageRenderer(bounds:panel.bounds).image {context in panel.layer.render(in:context.cgContext)}
        XCTAssertEqual(buttons,1,"Drawing must not emit feedback")
        time=0.2;XCTAssertTrue(key.accessibilityActivate());XCTAssertEqual(buttons,2)
    }

}

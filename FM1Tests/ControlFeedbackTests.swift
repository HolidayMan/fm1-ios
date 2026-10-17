import XCTest
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
}

import UIKit

/// Consume full detents and retain the signed fractional drag for reversals.
enum KnobDrag {
    static let pointsPerDetent:CGFloat=4
    static func update(anchorY:CGFloat,currentY:CGFloat)->(steps:Int,anchorY:CGFloat) {
        let steps=Int((anchorY-currentY)/pointsPerDetent)
        return (steps,anchorY-CGFloat(steps)*pointsPerDetent)
    }
}

/// One shared gate prevents a chord or a large drag event becoming a haptic burst.
struct HapticRateGate {
    private var last:TimeInterval?
    mutating func allow(at time:TimeInterval)->Bool {
        if let last,time-last<0.05 {return false}
        last=time;return true
    }
}

@MainActor final class ControlHaptics {
    static let shared:ControlHaptics = {
        // Use the standard light pulse: soft at 35% can be hard to feel as button
        // confirmation. Selection feedback and the shared burst cap stay intact.
        let press=UIImpactFeedbackGenerator(style:.light)
        let selection=UISelectionFeedbackGenerator()
        return ControlHaptics(button:{press.impactOccurred();press.prepare()},
                              detent:{selection.selectionChanged();selection.prepare()},
                              prepareButton:{press.prepare()})
    }()
    private let emitButton:()->Void,emitDetent:()->Void,warmButton:()->Void
    private let now:()->TimeInterval
    private var gate=HapticRateGate()
    // Injectable outputs verify dispatch without pretending a simulator has a Taptic Engine.
    init(button:@escaping ()->Void,detent:@escaping ()->Void,prepareButton:@escaping ()->Void={},now:@escaping ()->TimeInterval={ProcessInfo.processInfo.systemUptime}) {
        emitButton=button;emitDetent=detent;warmButton=prepareButton;self.now=now
    }
    func prepareButton() {warmButton()}
    func button() {
        guard gate.allow(at:now()) else{return}
        emitButton()
    }
    func detent() {
        guard gate.allow(at:now()) else{return}
        emitDetent()
    }
}

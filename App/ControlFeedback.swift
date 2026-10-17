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
    static let shared=ControlHaptics()
    private let press=UIImpactFeedbackGenerator(style:.soft)
    private let selection=UISelectionFeedbackGenerator()
    private var gate=HapticRateGate()
    private init() {}
    func button() {
        guard gate.allow(at:ProcessInfo.processInfo.systemUptime) else{return}
        press.impactOccurred(intensity:0.35);press.prepare()
    }
    func detent() {
        guard gate.allow(at:ProcessInfo.processInfo.systemUptime) else{return}
        selection.selectionChanged();selection.prepare()
    }
}

import Foundation

/// Default emulation rate. This controls binary CPU work per emulated second;
/// source-compiled audio engines keep their original sample-rate-driven timing.
enum EmulatorClock {
    static let defaultMHz=240
    static let allowedMHz=[120,180,240,320,360]
    static let preferenceKey="emulatorMHz"
    static func validated(_ value:Int)->Int {allowedMHz.contains(value) ? value : defaultMHz}
    static func title(_ value:Int)->String {"\(value) MHz" + (value == defaultMHz ? " · Default" : "")}
}

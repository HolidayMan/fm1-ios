import SwiftUI

/// High-frequency visual frames have their own subscription. Toolbar, catalogue
/// and settings only observe slower instrument state changes.
final class InstrumentDisplayState:ObservableObject {
    @Published var screen:CGImage?
    @Published var leds:[Float]=Array(repeating:0,count:41)
}

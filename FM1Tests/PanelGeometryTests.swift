import XCTest
import UIKit
@testable import FM1

final class PanelGeometryTests: XCTestCase {
    @MainActor func testVisibleKeysAndKeyboardGuttersHaveContinuousTargets() {
        // Landscape canvas after the transport, on small and wide phones.
        for size in [CGSize(width: 774, height: 355), CGSize(width: 860, height: 390)] {
            let panel = HardwarePanel(frame: CGRect(origin: .zero, size: size))
            panel.layoutIfNeeded()
            let elements = panel.accessibilityElements as! [UIAccessibilityElement]
            let first = elements.first {$0.accessibilityLabel == "F3"}!.accessibilityFrameInContainerSpace
            XCTAssertEqual(panel.pianoKey(at: CGPoint(x: first.midX, y: first.midY)), 14)
            // Previously these were dead zones: horizontal gutter and bottom casing.
            XCTAssertEqual(panel.pianoKey(at: CGPoint(x: first.maxX + 0.25, y: first.midY)), 14)
            XCTAssertEqual(panel.pianoKey(at: CGPoint(x: first.midX, y: size.height - 1)), 14)
            let keyboardHeight = min(240, max(118, size.height * 0.42))
            let keyboardTop = size.height - keyboardHeight - 3
            for y in stride(from: keyboardTop, to: size.height, by: 2) {
                for x in stride(from: CGFloat(0), to: size.width, by: 2) {
                    XCTAssertNotNil(panel.pianoKey(at: CGPoint(x: x, y: y)))
                }
            }
            for label in ["HOME", "MASTER", "Enlarge display"] {
                let rect = elements.first {$0.accessibilityLabel == label}!.accessibilityFrameInContainerSpace
                XCTAssertNil(panel.pianoKey(at: CGPoint(x: rect.midX, y: rect.midY)), "Keyboard must not steal \(label)")
            }
            XCTAssertNil(panel.pianoKey(at: CGPoint(x: first.midX, y: -1)))
            XCTAssertNil(panel.pianoKey(at: CGPoint(x: first.midX, y: size.height + 1)))
            XCTAssertNil(panel.pianoKey(at: CGPoint(x: -1, y: first.midY)))
        }
    }
}

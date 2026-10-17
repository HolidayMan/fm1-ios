import XCTest
import UIKit
@testable import FM1

final class PanelGeometryTests: XCTestCase {
    @MainActor func testFirmwareLampCannotPaintFingerSlitAndGuideStaysDim() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let instrument=Instrument(directory:directory)
        let panel=HardwarePanel(frame:CGRect(x:0,y:0,width:774,height:355))
        panel.instrument=instrument;panel.layoutIfNeeded()
        let elements=panel.accessibilityElements as! [UIAccessibilityElement]
        let key=try XCTUnwrap(elements.first {$0.accessibilityLabel == "F3"}).accessibilityFrameInContainerSpace
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.preferredRange = .standard
        func pixels(_ level:Float)throws->([UInt8],[UInt8]) {
            instrument.leds[14]=level
            let image=UIGraphicsImageRenderer(bounds:panel.bounds,format:format).image {_ in panel.draw(panel.bounds)}
            let cg=try XCTUnwrap(image.cgImage),data=try XCTUnwrap(cg.dataProvider?.data)
            XCTAssertEqual(cg.bitsPerPixel,32)
            let bytes=CFDataGetBytePtr(data)!
            func pixel(_ y:CGFloat)->[UInt8] {
                let offset=Int(y)*cg.bytesPerRow+Int(key.midX)*4
                return Array(UnsafeBufferPointer(start:bytes+offset,count:4))
            }
            return (pixel(key.minY+12),pixel(key.maxY-5))
        }
        let off=try pixels(0),guide=try pixels(4.0/1100.0),full=try pixels(95.0/1100.0)
        XCTAssertEqual(off.0,full.0,"Firmware activity must not impersonate a held finger")
        XCTAssertEqual(off.0,guide.0)
        XCTAssertGreaterThan(guide.1[1],off.1[1],"Firmware landmark must remain visible")
        XCTAssertLessThan(guide.1[1],full.1[1],"A dim landmark must not appear fully active")
    }

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

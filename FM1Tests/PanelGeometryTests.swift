import XCTest
import UIKit
@testable import FM1

final class PanelGeometryTests: XCTestCase {
    @MainActor func testFirmwareLampUsesCentralInsertWhileBottomOfKeyStaysUnlit() throws {
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
            panel.refreshDisplay()
            let image=UIGraphicsImageRenderer(bounds:panel.bounds,format:format).image {context in panel.layer.render(in:context.cgContext)}
            let cg=try XCTUnwrap(image.cgImage),data=try XCTUnwrap(cg.dataProvider?.data)
            XCTAssertEqual(cg.bitsPerPixel,32)
            let bytes=CFDataGetBytePtr(data)!
            func pixel(_ y:CGFloat)->[UInt8] {
                let offset=Int(y)*cg.bytesPerRow+Int(key.midX)*4
                return Array(UnsafeBufferPointer(start:bytes+offset,count:4))
            }
            return (pixel(key.minY+20),pixel(key.maxY-5))
        }
        let off=try pixels(0),dim=try pixels(4.0/1100.0),full=try pixels(95.0/1100.0)
        XCTAssertGreaterThan(dim.0[1],off.0[1],"Nonzero firmware duty must be visible in the existing central insert")
        XCTAssertLessThan(dim.0[1],full.0[1],"Dim firmware duty must remain distinct from active")
        XCTAssertEqual(off.1,dim.1);XCTAssertEqual(off.1,full.1,"There must be no separate bottom lamp")
    }

    @MainActor func testHidingTransportKeepsEveryKnobDiameterAndGrowsLCDWithoutOverlaps() throws {
        for compact in [CGSize(width:720,height:343),CGSize(width:774,height:355),CGSize(width:832,height:408)] {
            let panel=HardwarePanel(frame:CGRect(origin:.zero,size:compact))
            panel.knobReferenceHeight=compact.height;panel.layoutIfNeeded()
            func rect(_ name:String)throws->CGRect {
                let controls=try XCTUnwrap(panel.accessibilityElements as? [UIAccessibilityElement])
                return try XCTUnwrap(controls.first{$0.accessibilityLabel==name}).accessibilityFrameInContainerSpace
            }
            let names=["MASTER","SELECT","PRESETS","ALGORITHM","KNOB1","KNOB2","KNOB3","KNOB4"]
            func checkCluster()throws {
                let a=try rect("MASTER"),b=try rect("SELECT"),c=try rect("PRESETS"),d=try rect("ALGORITHM")
                XCTAssertEqual(a.minY,b.minY,accuracy:0.001);XCTAssertEqual(c.minY,d.minY,accuracy:0.001)
                XCTAssertEqual(a.minX,c.minX,accuracy:0.001);XCTAssertEqual(b.minX,d.minX,accuracy:0.001)
                XCTAssertEqual(b.minX-a.maxX,c.minY-a.maxY,accuracy:0.001,"The2×2 cluster must have the same spacing in both axes")
                XCTAssertGreaterThan(c.minY-a.maxY,0)
            }
            try checkCluster()
            let original=try names.map{try rect($0)}
            let originalCluster=original.prefix(4).reduce(CGRect.null){$0.union($1)}
            let originalOctave=try rect("OCT−")
            let originalRightGap=try rect("FX").minY-original[4].maxY
            XCTAssertEqual(original[4].minY-15,originalRightGap,accuracy:0.001,"Center the visible right labels and faces above the buttons in compact view")
            let smallLCD=try rect("Enlarge display")
            panel.bounds.size.height += 32;panel.setNeedsLayout();panel.layoutIfNeeded()
            let bigLCD=try rect("Enlarge display")
            try checkCluster()
            let grownCluster=try names.prefix(4).map{try rect($0)}.reduce(CGRect.null){$0.union($1)}
            XCTAssertEqual(grownCluster.width,originalCluster.width,accuracy:0.001)
            XCTAssertEqual(grownCluster.height,originalCluster.height,accuracy:0.001,"The left block moves as one rigid group")
            XCTAssertEqual(grownCluster.midX,originalCluster.midX,accuracy:0.001)
            XCTAssertEqual(grownCluster.midY-originalCluster.midY,(try rect("OCT−").minY-originalOctave.minY)/2,accuracy:0.001,"Center the whole block in the changing space above octave keys")
            for (index,name) in names.enumerated() where index>=4 {
                let next=try rect(name)
                XCTAssertEqual(try rect("FX").minY-next.maxY,originalRightGap,accuracy:0.001,"Right knobs retain their gap above the function keys")
                XCTAssertEqual(try rect("OCT−").minY-next.maxY,originalOctave.minY-original[index].maxY,accuracy:0.001,"The right row is anchored to the panel bottom")
            }
            XCTAssertGreaterThan(bigLCD.width,smallLCD.width+1)
            XCTAssertEqual(bigLCD.width,bigLCD.height,accuracy:0.001)
            for (name,previous) in zip(names,original) {
                let knob=try rect(name)
                XCTAssertEqual(knob.width,previous.width,accuracy:0.001,"\(name) must not grow with the LCD")
                XCTAssertEqual(knob.height,previous.height,accuracy:0.001)
                XCTAssertFalse(knob.intersects(bigLCD),"Expanded LCD must not cover \(name)")
            }
            for name in ["FX","SEL","ENV","LFO","EDIT","GLO","HOME","SAVE","ARP","SEQ","PLAY STOP","REC"] {
                let button=try rect(name)
                XCTAssertGreaterThanOrEqual(button.width,44-0.001)
                XCTAssertFalse(button.intersects(bigLCD))
            }
            panel.bounds.size=compact;panel.setNeedsLayout();panel.layoutIfNeeded()
            for (name,previous) in zip(names,original) {XCTAssertEqual(try rect(name),previous)}
        }
    }

    @MainActor func testTransientInvalidKnobReferenceUsesValidPanelGeometry() throws {
        let panel=HardwarePanel(frame:CGRect(x:0,y:0,width:774,height:355));panel.layoutIfNeeded()
        func master()throws->CGRect {
            let elements=try XCTUnwrap(panel.accessibilityElements as? [UIAccessibilityElement])
            return try XCTUnwrap(elements.first{$0.accessibilityLabel=="MASTER"}).accessibilityFrameInContainerSpace
        }
        let baseline=try master()
        for transient in [CGFloat.zero,-32,100,.nan,.infinity] {
            panel.knobReferenceHeight=transient;panel.layoutIfNeeded()
            XCTAssertEqual(try master(),baseline,"An intermediate reference must never rasterize invalid controls")
        }
        panel.knobReferenceHeight=323;panel.layoutIfNeeded()
        XCTAssertGreaterThan(try master().width,0)
        XCTAssertLessThan(try master().width,baseline.width)
    }

    @MainActor func testUpperKeysCenterBetweenTheirLowerNeighbours() throws {
        for size in [CGSize(width:774,height:355),CGSize(width:774,height:390),CGSize(width:574,height:302)] {
            let panel=HardwarePanel(frame:CGRect(origin:.zero,size:size));panel.layoutIfNeeded()
            let elements=try XCTUnwrap(panel.accessibilityElements as? [UIAccessibilityElement])
            func rect(_ name:String)throws->CGRect {try XCTUnwrap(elements.first {$0.accessibilityLabel == name}).accessibilityFrameInContainerSpace}
            // F# sits between F/G, G# between G/A; row spacing must not bias right.
            for (upper,lowerLeft,lowerRight) in [("F sharp3","F3","G3"),("G sharp3","G3","A3"),("A sharp3","A3","B3")] {
                let a=try rect(lowerLeft),b=try rect(lowerRight),key=try rect(upper)
                XCTAssertEqual(key.midX,(a.midX+b.midX)/2,accuracy:0.001)
                XCTAssertLessThan(key.maxY,a.minY)
            }
        }
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

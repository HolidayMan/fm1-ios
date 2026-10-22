import XCTest
import UIKit
@testable import FM1

final class PanelRenderingTests:XCTestCase {
    @MainActor private func fixture() -> (HardwarePanel,Instrument,URL) {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let instrument=Instrument(directory:directory)
        let panel=HardwarePanel(frame:CGRect(x:0,y:0,width:774,height:355))
        panel.contentScaleFactor=1;panel.instrument=instrument;panel.layoutIfNeeded()
        return (panel,instrument,directory)
    }
    @MainActor private func layer(_ name:String,_ panel:HardwarePanel) throws -> CALayer {
        try XCTUnwrap(panel.layer.sublayers?.first{$0.name==name})
    }
    @MainActor private func control(_ name:String,_ panel:HardwarePanel) throws -> UIAccessibilityElement {
        try XCTUnwrap((panel.accessibilityElements as? [UIAccessibilityElement])?.first{$0.accessibilityLabel==name})
    }
    @MainActor func testFirmwareSnapshotsReuseRasterizedArtworkAndLayerContents() throws {
        let (panel,instrument,directory)=fixture();defer{try? FileManager.default.removeItem(at:directory)}
        XCTAssertEqual(panel.artworkBuildCount,1)
        let background=try layer("Panel artwork",panel)
        let initial=try XCTUnwrap(background.contents) as! CGImage
        let lamp=try layer("Firmware lamp 14",panel)
        let initialLamp=try XCTUnwrap(lamp.contents) as! CGImage
        XCTAssertEqual(initial.width,774);XCTAssertEqual(initial.height,355);XCTAssertEqual(initial.bitsPerComponent,8)
        let screen=UIGraphicsImageRenderer(size:CGSize(width:2,height:2)).image {context in
            UIColor.red.setFill();context.fill(CGRect(x:0,y:0,width:2,height:2))
        }.cgImage!
        instrument.screen=screen
        for i in 0..<120 {
            instrument.leds[14]=i%2==0 ? 95.0/1100.0 : 4.0/1100.0
            panel.refreshDisplay()
        }
        XCTAssertEqual(panel.artworkBuildCount,1,"LCD and firmware activity must not rasterize body or controls again")
        let final=try XCTUnwrap(background.contents) as! CGImage
        XCTAssertTrue(initial === final,"Artwork is an actual retained bitmap, not rebuilt gradients")
        let displayed=try XCTUnwrap(try layer("Firmware LCD",panel).contents) as! CGImage
        XCTAssertTrue(displayed === screen)
        XCTAssertEqual(lamp.opacity,PanelPalette.lampOpacity(4.0/1100.0),accuracy:0.00001)
        XCTAssertTrue(initialLamp === (try XCTUnwrap(lamp.contents) as! CGImage),"Halo bitmap must be reused across firmware frames")
        XCTAssertEqual(lamp.shadowOpacity,0,"Halo is cached pixels, not a live blur pass")
        XCTAssertFalse(lamp.masksToBounds)
    }
    @MainActor func testArtworkInvalidatesForBoundsScaleAndFinishOnly() throws {
        let (panel,_,directory)=fixture();defer{try? FileManager.default.removeItem(at:directory)}
        panel.finish = .black;panel.refreshDisplay();panel.setNeedsLayout();panel.layoutIfNeeded()
        XCTAssertEqual(panel.artworkBuildCount,1)
        panel.finish = .coolGray
        XCTAssertEqual(panel.artworkBuildCount,2)
        panel.refreshDisplay();XCTAssertEqual(panel.artworkBuildCount,2)
        panel.contentScaleFactor=2;panel.refreshDisplay()
        XCTAssertEqual(panel.artworkBuildCount,3)
        XCTAssertEqual(panel.artworkPixelSize,CGSize(width:1548,height:710))
        panel.bounds.size=CGSize(width:824,height:387);panel.setNeedsLayout();panel.layoutIfNeeded()
        XCTAssertEqual(panel.artworkBuildCount,4)
        XCTAssertEqual(panel.artworkPixelSize,CGSize(width:1648,height:774))
        let count=panel.layer.sublayers?.count
        for finish in PanelFinish.allCases {panel.finish=finish;panel.refreshDisplay()}
        XCTAssertEqual(panel.layer.sublayers?.count,count,"Changing finishes replaces active layers rather than accumulating caches")
    }
    @MainActor func testSnapshotBeforePendingLayoutCannotCacheOldControlGeometry() throws {
        let (panel,_,directory)=fixture();defer{try? FileManager.default.removeItem(at:directory)}
        let oldScreen=try layer("Firmware LCD",panel).frame
        let oldBuilds=panel.artworkBuildCount
        panel.bounds.size=CGSize(width:824,height:420)
        panel.refreshDisplay() // A snapshot arrives before UIKit services its layout.
        XCTAssertEqual(panel.artworkBuildCount,oldBuilds,"Pending geometry must not enter the raster cache")
        panel.layoutIfNeeded()
        let newScreen=try control("Enlarge display",panel).accessibilityFrameInContainerSpace
        XCTAssertNotEqual(newScreen,oldScreen)
        XCTAssertEqual(try layer("Firmware LCD",panel).frame,newScreen)
        XCTAssertEqual(try layer("Panel artwork",panel).frame,panel.bounds)
        XCTAssertEqual(panel.artworkPixelSize,CGSize(width:824,height:420))
        XCTAssertEqual(panel.artworkBuildCount,oldBuilds+1)
        let key=try control("F3",panel).accessibilityFrameInContainerSpace
        let pressedFrame=try layer("Pressed key 14",panel).frame
        XCTAssertEqual(pressedFrame.minX,key.minX,accuracy:0.001)
        XCTAssertEqual(pressedFrame.minY,key.minY,accuracy:0.001)
        XCTAssertEqual(pressedFrame.width,key.width,accuracy:0.001)
        XCTAssertEqual(pressedFrame.height,key.height,accuracy:0.001)
    }
    @MainActor func testTinyTransientBoundsDeferRasterizationAndNarrowLayoutRecovers() throws {
        let panel=HardwarePanel(frame:CGRect(x:0,y:0,width:100,height:80))
        panel.contentScaleFactor=1;panel.layoutIfNeeded()
        XCTAssertEqual(panel.artworkBuildCount,0)
        XCTAssertEqual(panel.artworkPixelSize,.zero)
        XCTAssertTrue(panel.accessibilityElementsHidden)
        panel.bounds.size=CGSize(width:774,height:355);panel.setNeedsLayout();panel.layoutIfNeeded()
        XCTAssertEqual(panel.artworkBuildCount,1)
        XCTAssertFalse(panel.accessibilityElementsHidden)
        panel.bounds.size=CGSize(width:420,height:190);panel.setNeedsLayout();panel.layoutIfNeeded()
        panel.refreshDisplay()
        XCTAssertEqual(panel.artworkBuildCount,1,"Tiny transition frames must not allocate malformed control bitmaps")
        XCTAssertTrue(try layer("Panel artwork",panel).isHidden)
        for width:CGFloat in [320,420,774] {
            panel.bounds.size=CGSize(width:width,height:355);panel.setNeedsLayout();panel.layoutIfNeeded()
            let screen=try control("Enlarge display",panel).accessibilityFrameInContainerSpace
            XCTAssertGreaterThan(screen.width,0);XCTAssertGreaterThan(screen.height,0)
            XCTAssertEqual(try layer("Firmware LCD",panel).frame,screen)
            XCTAssertEqual(panel.artworkPixelSize,CGSize(width:width,height:355))
            XCTAssertFalse(try layer("Panel artwork",panel).isHidden)
            XCTAssertFalse(try layer("Knob marker 1",panel).isHidden)
            XCTAssertFalse(panel.accessibilityElementsHidden)
        }
        XCTAssertEqual(panel.artworkBuildCount,4)
    }
    @MainActor func testFingerFeedbackAndKnobRotationDoNotInvalidateArtwork() throws {
        let (panel,instrument,directory)=fixture();defer{try? FileManager.default.removeItem(at:directory)}
        let key=try control("F3",panel),pressed=try layer("Pressed key 14",panel)
        XCTAssertTrue(pressed.isHidden)
        XCTAssertTrue(key.accessibilityActivate())
        XCTAssertEqual(key.accessibilityValue,"Pressed")
        XCTAssertFalse(pressed.isHidden,"Finger feedback is immediate, independent of firmware LED snapshots")
        XCTAssertEqual(try layer("Firmware lamp 14",panel).opacity,0)
        let marker=try layer("Knob marker 1",panel),rotation=marker.affineTransform()
        try control("SELECT",panel).accessibilityIncrement()
        XCTAssertNotEqual(marker.affineTransform(),rotation)
        let master=try layer("Knob marker 0",panel),masterRotation=master.affineTransform()
        instrument.volume=0.2;panel.refreshDisplay()
        XCTAssertNotEqual(master.affineTransform(),masterRotation)
        panel.finish = .purple
        XCTAssertFalse(try layer("Pressed key 14",panel).isHidden,"A finish change must retain the finger's held state")
        XCTAssertEqual(panel.artworkBuildCount,2)
        panel.bounds.size.height += 32;panel.setNeedsLayout();panel.layoutIfNeeded()
        XCTAssertEqual(key.accessibilityValue,"Pressed","Header relayout must not release a held note")
        XCTAssertFalse(try layer("Pressed key 14",panel).isHidden)
        XCTAssertEqual(panel.artworkBuildCount,3)
        XCTAssertEqual(panel.accessibilityIdentifier,"Instrument panel");XCTAssertFalse(panel.isAccessibilityElement)
    }
    @MainActor func testAllSixFinishesRenderDistinctOffDimAndActiveCachedHalos() throws {
        let (panel,instrument,directory)=fixture();defer{try? FileManager.default.removeItem(at:directory)}
        let key=try control("F3",panel).accessibilityFrameInContainerSpace
        let function=try control("PLAY STOP",panel).accessibilityFrameInContainerSpace
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.preferredRange = .standard
        func pixel(_ image:CGImage,_ point:CGPoint)->[UInt8] {
            let data=image.dataProvider!.data!,bytes=CFDataGetBytePtr(data)!
            let offset=Int(point.y)*image.bytesPerRow+Int(point.x)*4
            return Array(UnsafeBufferPointer(start:bytes+offset,count:3))
        }
        func energy(_ image:CGImage,_ point:CGPoint)->Int {pixel(image,point).map(Int.init).reduce(0,+)}
        func render(_ level:Float,_ name:String)->CGImage {
            instrument.leds[14]=level;instrument.leds[12]=level
            panel.refreshDisplay()
            let image=UIGraphicsImageRenderer(bounds:panel.bounds,format:format).image {context in panel.layer.render(in:context.cgContext)}
            let attachment=XCTAttachment(image:image);attachment.name="Key halo · \(panel.finish.rawValue) · \(name)";attachment.lifetime = .keepAlways;add(attachment)
            return image.cgImage!
        }
        let core=CGPoint(x:key.midX,y:key.minY+20)
        // Sample inside the recessed lip, not its outer antialiased boundary.
        let lip=CGPoint(x:key.midX-2.5,y:key.minY+20)
        let face=CGPoint(x:key.midX-8,y:key.minY+20)
        let halo=CGPoint(x:key.midX+5,y:key.minY+20)
        let oldDash=CGPoint(x:key.midX,y:key.maxY-5)
        let functionCore=CGPoint(x:function.midX,y:function.minY+4)
        for finish in PanelFinish.allCases {
            panel.finish=finish
            let off=render(0,"off"),dim=render(4.0/1100.0,"dim firmware duty"),full=render(95.0/1100.0,"active firmware duty")
            XCTAssertGreaterThan(energy(dim,core)-energy(off,core),100,"\(finish.rawValue): dim core must be clearly distinct from off")
            XCTAssertGreaterThan(energy(dim,core)-energy(dim,lip),70,"\(finish.rawValue): recessed lip must frame the dim emitter")
            let faceDifference=zip(pixel(dim,core),pixel(dim,face)).map{abs(Int($0.0)-Int($0.1))}.reduce(0,+)
            XCTAssertGreaterThan(faceDifference,50,"\(finish.rawValue): dim emitter must separate from the surrounding key face")
            XCTAssertGreaterThan(energy(full,core)-energy(dim,core),200,"\(finish.rawValue): dim must remain substantially below active")
            XCTAssertGreaterThan(energy(full,halo)-energy(off,halo),3,"\(finish.rawValue): localized halo must extend outside the insert")
            XCTAssertGreaterThan(energy(dim,functionCore)-energy(off,functionCore),100,"\(finish.rawValue): function keys retain the top lamp")
            XCTAssertEqual(pixel(off,oldDash),pixel(dim,oldDash));XCTAssertEqual(pixel(off,oldDash),pixel(full,oldDash),"No separate bottom dash")
            let lamp=try layer("Firmware lamp 14",panel)
            let emitter=lamp.frame.insetBy(dx:12,dy:12),expected=CGRect(x:key.midX-2,y:key.minY+10,width:4,height:max(16,key.height*0.4))
            XCTAssertEqual(emitter.minX,expected.minX,accuracy:0.0001)
            XCTAssertEqual(emitter.minY,expected.minY,accuracy:0.0001)
            XCTAssertEqual(emitter.width,expected.width,accuracy:0.0001)
            XCTAssertEqual(emitter.height,expected.height,accuracy:0.0001)
            XCTAssertEqual(try control("F3",panel).accessibilityFrameInContainerSpace,key,"Lighting must not change geometry")
            let firmwareOpacityBeforeTouch=lamp.opacity
            XCTAssertTrue(try control("F3",panel).accessibilityActivate())
            XCTAssertEqual(lamp.opacity,firmwareOpacityBeforeTouch,"Touch cannot override the firmware duty")
            instrument.leds[14]=0;panel.refreshDisplay()
            XCTAssertEqual(lamp.opacity,0,"A held note must not invent a firmware lamp")
        }
    }
    @MainActor func testBlackLampBitmapMatchesBuild18RendererExactly() throws {
        let (panel,_,directory)=fixture();defer{try? FileManager.default.removeItem(at:directory)}
        panel.finish = .black
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.preferredRange = .standard;format.opaque=false
        // Independent frozen build18 drawing recipe, without a private screenshot
        // path or owner fixture. Cover both the piano and horizontal function lamp.
        for id in [14,12] {
            let lamp=try layer("Firmware lamp \(id)",panel)
            let actual=try XCTUnwrap(lamp.contents) as! CGImage
            let legacy=UIGraphicsImageRenderer(size:lamp.bounds.size,format:format).image {context in
                let emitter=CGRect(origin:.zero,size:lamp.bounds.size).insetBy(dx:12,dy:12)
                context.cgContext.saveGState()
                context.cgContext.setShadow(offset:.zero,blur:7,color:UIColor(red:186.0/255,green:1,blue:173.0/255,alpha:0.68).cgColor)
                UIColor(red:248.0/255,green:1,blue:247.0/255,alpha:1).setFill()
                UIBezierPath(roundedRect:emitter,cornerRadius:2).fill()
                context.cgContext.restoreGState()
            }.cgImage!
            XCTAssertEqual(actual.width,legacy.width);XCTAssertEqual(actual.height,legacy.height)
            XCTAssertEqual(actual.bytesPerRow,legacy.bytesPerRow)
            XCTAssertEqual(actual.dataProvider!.data! as Data,legacy.dataProvider!.data! as Data,"Black's emitter/halo must retain its exact build18 bitmap")
        }
    }
    @MainActor func testTouchFeedbackKeepsKeyFaceInkAndPerimeterStable() throws {
        let (panel,_,directory)=fixture();defer{try? FileManager.default.removeItem(at:directory)}
        let key=try control("F3",panel)
        for finish in PanelFinish.allCases {
            panel.finish=finish
            let base=try XCTUnwrap(try layer("Panel artwork",panel).contents) as! CGImage
            let held=try XCTUnwrap(try layer("Pressed key 14",panel).contents) as! CGImage
            func bytes(_ image:CGImage,_ point:CGPoint)->[UInt8] {
                let data=image.dataProvider!.data!,pointer=CFDataGetBytePtr(data)!
                let offset=Int(point.y)*image.bytesPerRow+Int(point.x)*4
                return Array(UnsafeBufferPointer(start:pointer+offset,count:3))
            }
            let rect=key.accessibilityFrameInContainerSpace
            for point in [CGPoint(x:10,y:rect.height*0.7),CGPoint(x:0,y:rect.height/2)] {
                let normal=bytes(base,CGPoint(x:rect.minX+point.x,y:rect.minY+point.y)),pressed=bytes(held,point)
                // Separate cached sprites may land on a different subpixel phase.
                // Compare the face with a small raster tolerance; the outer edge
                // may antialias, but must never become a bright touch outline.
                if point.x>0 {
                    for (a,b) in zip(normal,pressed) {XCTAssertLessThanOrEqual(abs(Int(a)-Int(b)),3,"\(finish.rawValue): stable key face")}
                } else {
                    XCTAssertLessThanOrEqual(pressed.map(Int.init).reduce(0,+),normal.map(Int.init).reduce(0,+)+12,"\(finish.rawValue): no luminous touch perimeter")
                }
            }
            XCTAssertNotEqual(bytes(base,CGPoint(x:rect.midX+10,y:rect.minY+2)),bytes(held,CGPoint(x:rect.width/2+10,y:2)),"\(finish.rawValue): immediate inset touch shade remains visible")
        }
    }
}

extension PanelRenderingTests {
    func testHeaderRelayoutReanchorsOneKnobMoveWithoutPhantomDetents() {
        var anchor=PanelKnobDragAnchor()
        let partial=anchor.update(anchorY:100,currentY:97)
        XCTAssertEqual(partial.steps,0);XCTAssertEqual(partial.anchorY,100)
        anchor.geometryChanged()
        let shifted=anchor.update(anchorY:partial.anchorY,currentY:132)
        XCTAssertEqual(shifted.steps,0);XCTAssertEqual(shifted.anchorY,132)
        let actualDrag=anchor.update(anchorY:shifted.anchorY,currentY:124)
        XCTAssertEqual(actualDrag.steps,2);XCTAssertEqual(actualDrag.anchorY,124)
        let reversal=anchor.update(anchorY:actualDrag.anchorY,currentY:128)
        XCTAssertEqual(reversal.steps,-1)
    }
}

import XCTest
@testable import FM1

final class PanelPaletteTests:XCTestCase {
    func testAllSixFinishesHaveReadableBodyNormalAndPressedLegends() {
        for finish in PanelFinish.allCases {
            let p=finish.palette
            for surface in [p.body,p.bodyBottom] {XCTAssertGreaterThanOrEqual(PanelPalette.contrast(p.ink,surface),4.5,"\(finish.rawValue) body labels")}
            for surface in [p.control,p.controlBottom] {XCTAssertGreaterThanOrEqual(PanelPalette.contrast(p.controlInk,surface),4.5,"\(finish.rawValue) control legends")}
            for surface in [p.pressed,p.pressedBottom] {XCTAssertGreaterThanOrEqual(PanelPalette.contrast(p.pressedInk,surface),4.5,"\(finish.rawValue) held legends")}
            XCTAssertGreaterThanOrEqual(PanelPalette.contrast(p.led,0x111719),4.5,"\(finish.rawValue) header accent")
        }
        XCTAssertEqual(Set(PanelFinish.allCases.map{$0.palette.led}).count,6)
        XCTAssertEqual(Set(PanelFinish.allCases.map{$0.palette.pressed}).count,6)
    }
    func testLampDisplayCurvePreservesDutyOrderAndExactOffWithoutBrightFloor() {
        XCTAssertEqual(PanelPalette.firmwareOpacity(95.0/1100.0),1,accuracy:0.00001)
        XCTAssertEqual(PanelPalette.firmwareOpacity(4.0/1100.0),4.0/95.0,accuracy:0.00001)
        XCTAssertLessThan(PanelPalette.firmwareOpacity(4.0/1100.0),0.05)
        XCTAssertEqual(PanelPalette.firmwareOpacity(0),0)
        XCTAssertEqual(PanelPalette.firmwareOpacity(-1),0)
        XCTAssertEqual(PanelPalette.firmwareOpacity(.nan),0)
        XCTAssertEqual(PanelPalette.firmwareOpacity(.infinity),0)
        XCTAssertEqual(PanelPalette.firmwareOpacity(10),1)
        XCTAssertEqual(PanelPalette.lampOpacity(0),0)
        XCTAssertEqual(PanelPalette.lampOpacity(-1),0)
        XCTAssertEqual(PanelPalette.lampOpacity(.nan),0)
        XCTAssertEqual(PanelPalette.lampOpacity(.infinity),0)
        XCTAssertEqual(PanelPalette.lampOpacity(95.0/1100.0),1,accuracy:0.00001)
        let dim=PanelPalette.lampOpacity(4.0/1100.0)
        XCTAssertGreaterThan(dim,0.55,"Small low-duty inserts need enough light to separate from mid-tone finishes")
        XCTAssertLessThan(dim,0.7,"Dim firmware duty must still have a clear active-state headroom")
        XCTAssertLessThan(PanelPalette.lampOpacity(1e-9),0.005,"Tiny nonzero duty must not jump to a minimum on state")
        var previous:Float=0
        for value in 1...1100 {
            let next=PanelPalette.lampOpacity(Float(value)/1100)
            XCTAssertGreaterThanOrEqual(next,previous);previous=next
        }
    }
    func testFinishSpecificLampOpticsKeepBlackExactAndColoredSeatsSubtle() {
        let black=PanelFinish.black.lampStyle
        XCTAssertEqual(black,PanelLampStyle(core:0xf8fff7,halo:0xbaffad,recess:0x18251c,haloAlpha:0.68,haloBlur:7,recessInset:2,recessRadius:4),"Black build18 optical tokens are a fixed baseline")
        XCTAssertEqual(Set(PanelFinish.allCases.map{$0.lampStyle.core}).count,6)
        XCTAssertEqual(Set(PanelFinish.allCases.map{$0.lampStyle.halo}).count,6)
        for finish in PanelFinish.allCases {
            let lamp=finish.lampStyle
            XCTAssertGreaterThanOrEqual(PanelPalette.contrast(lamp.core,lamp.recess),7,"\(finish.rawValue): active emitter must remain clear against its seat")
            if finish != .black {
                XCTAssertLessThan(lamp.recessInset,black.recessInset,"Colored faces must not inherit Black's heavy seat")
                XCTAssertLessThan(lamp.haloAlpha,black.haloAlpha)
                XCTAssertLessThan(lamp.haloBlur,black.haloBlur,"Colored halos remain localized instead of washing the key face")
            }
        }
    }
}

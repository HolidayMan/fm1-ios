import XCTest
final class FM1UITests: XCTestCase {
    func testLocalFirmwarePlaybackAndSwitching() throws {
        let app=XCUIApplication();app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.buttons["Firmware library"].tap()
        let stock=findInstalled("Stock-V15",in:app)
        guard stock.exists else {throw XCTSkip("Seed both local firmware fixtures to run binary integration coverage.")}
        stock.tap()
        XCTAssertTrue(app.buttons["Pause instrument"].waitForExistence(timeout:15))
        app.buttons["C4"].press(forDuration:0.7)
        app.buttons["FX"].tap()
        app.buttons["HOME"].tap()
        let stockImage=XCTAttachment(screenshot:XCUIScreen.main.screenshot());stockImage.name="Stock V15 native panel";stockImage.lifetime = .keepAlways;add(stockImage)
        app.buttons["Pause instrument"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout:5))
        app.buttons["Resume instrument"].tap()
        XCTAssertTrue(app.buttons["Pause instrument"].waitForExistence(timeout:10))
        app.buttons["Firmware library"].tap()
        let felucca=findInstalled("Felucca-1.6.1",in:app)
        guard felucca.exists else {throw XCTSkip("Seed both local firmware fixtures to run binary integration coverage.")}
        felucca.tap()
        XCTAssertTrue(app.buttons["Pause instrument"].waitForExistence(timeout:15))
        app.buttons["C4"].press(forDuration:0.7)
        let feluccaImage=XCTAttachment(screenshot:XCUIScreen.main.screenshot());feluccaImage.name="Felucca native panel";feluccaImage.lifetime = .keepAlways;add(feluccaImage)
    }
    private func findInstalled(_ prefix:String,in app:XCUIApplication)->XCUIElement {
        let search=app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:5))
        search.tap();search.typeText(prefix+"\n")
        let match=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",prefix)).firstMatch
        _=match.waitForExistence(timeout:3)
        if match.exists && !match.isHittable {app.collectionViews.firstMatch.swipeUp()}
        return match
    }
    func testHardwarePanelAndLibrary() {
        let app=XCUIApplication();app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Firmware library"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["F3"].exists)
        XCTAssertTrue(app.buttons["G5"].exists)
        XCTAssertTrue(app.buttons["HOME"].exists)
        app.buttons["Firmware library"].tap()
        XCTAssertTrue(app.buttons["Import .fwsc from Files"].waitForExistence(timeout:5))
        app.buttons["Done"].tap()
        app.buttons["Enlarge display"].tap()
        XCTAssertTrue(app.staticTexts["No firmware running"].waitForExistence(timeout:5))
        app.buttons["Done"].tap()
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot());attachment.name="FM1 landscape panel";attachment.lifetime = .keepAlways;add(attachment)
    }
}

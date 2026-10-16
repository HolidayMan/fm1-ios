import XCTest

final class PanelUITests:XCTestCase {
    func testLandscapeControlsFillPhoneAndColorsPersist() {
        let app=XCUIApplication();app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let home=app.buttons["HOME"]
        XCTAssertTrue(home.waitForExistence(timeout:10))
        XCTAssertGreaterThanOrEqual(home.frame.width,44)
        XCTAssertGreaterThanOrEqual(home.frame.height,40)
        XCTAssertGreaterThanOrEqual(app.descendants(matching:.any).matching(identifier:"MASTER").firstMatch.frame.width,44)
        let first=app.buttons["F3"], last=app.buttons["G5"]
        XCTAssertGreaterThanOrEqual(first.frame.width,40)
        XCTAssertLessThan(app.frame.maxY-first.frame.maxY,12,"Keyboard should use the bottom of the screen")
        XCTAssertGreaterThan(last.frame.maxX-first.frame.minX,app.frame.width*0.83)
        app.buttons["Panel color"].tap()
        let whiteBlue=app.buttons["Finish White-Blue"]
        XCTAssertTrue(whiteBlue.waitForExistence(timeout:5))
        if !whiteBlue.isHittable {app.swipeUp()}
        whiteBlue.tap()
        XCTAssertEqual(app.buttons["Panel color"].value as? String,"White-Blue")
        let white=XCTAttachment(screenshot:XCUIScreen.main.screenshot());white.name="iPhone 12 White-Blue full panel";white.lifetime = .keepAlways;add(white)
        app.terminate();app.launch()
        XCTAssertEqual(app.buttons["Panel color"].value as? String,"White-Blue")
        app.buttons["Panel color"].tap()
        app.buttons["Finish Black-Green"].tap()
        let green=XCTAttachment(screenshot:XCUIScreen.main.screenshot());green.name="iPhone 12 Black-Green full panel";green.lifetime = .keepAlways;add(green)
    }
    private func reveal(_ element:XCUIElement,in app:XCUIApplication)->Bool {
        for _ in 0..<4 {
            if element.exists && element.isHittable {return true}
            app.collectionViews.firstMatch.swipeUp()
        }
        return element.exists && element.isHittable
    }
    private func waitForFirmware(_ prefix:String,in app:XCUIApplication) {
        let selected=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label BEGINSWITH %@",prefix),object:app.buttons["Firmware library"])
        XCTAssertEqual(XCTWaiter.wait(for:[selected],timeout:60),.completed,"The downloaded firmware must actually become selected")
        XCTAssertTrue(app.buttons["Pause instrument"].waitForExistence(timeout:15))
    }
    func testCatalogueDownloadStockAndFelucca() {
        let app=XCUIApplication();app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.buttons["Firmware library"].tap()
        let initialSearch=app.searchFields.firstMatch
        XCTAssertTrue(initialSearch.waitForExistence(timeout:5));initialSearch.tap();initialSearch.typeText("Stock\n")
        let stock=app.buttons["Download Stock"]
        XCTAssertTrue(reveal(stock,in:app))
        stock.tap()
        waitForFirmware("Stock-V15",in:app)
        app.buttons["C4"].press(forDuration:0.5)
        app.buttons["HOME"].tap()
        let stockImage=XCTAttachment(screenshot:XCUIScreen.main.screenshot());stockImage.name="iPhone 12 catalogue stock boot";stockImage.lifetime = .keepAlways;add(stockImage)
        app.buttons["Firmware library"].tap()
        let search=app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:5));search.tap();search.typeText("Felucca\n")
        let felucca=app.buttons["Download Felucca"]
        XCTAssertTrue(reveal(felucca,in:app));felucca.tap()
        waitForFirmware("Felucca-1.6.1",in:app)
        app.buttons["C4"].press(forDuration:0.5)
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name="iPhone 12 catalogue Felucca boot";image.lifetime = .keepAlways;add(image)
    }
}

import XCTest
import Combine
import CryptoKit
@testable import FM1

final class UIResponsivenessTests:XCTestCase {
    @MainActor func testDisplayFramesDoNotInvalidateInstrumentMenus()throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite="UIResponsiveness.\(UUID().uuidString)"
        let preferences=UserDefaults(suiteName:suite)!
        defer {try? FileManager.default.removeItem(at:directory);preferences.removePersistentDomain(forName:suite)}
        let instrument=Instrument(directory:directory,preferences:preferences)
        var menuUpdates=0,frameUpdates=0
        let menuSubscription=instrument.objectWillChange.sink {menuUpdates += 1}
        let displaySubscription=instrument.displayState.objectWillChange.sink {frameUpdates += 1}
        for i in 0..<30 {
            instrument.screen=nil
            instrument.leds=Array(repeating:Float(i%2),count:41)
        }
        XCTAssertEqual(menuUpdates,0,"Firmware display updates must not rebuild menus or reload the catalogue")
        XCTAssertGreaterThanOrEqual(frameUpdates,30,"The panel still needs live display updates")
        withExtendedLifetime((menuSubscription,displaySubscription)) {}
    }
    func testDownloadedFirmwareStagingValidatesBeforeCreatingPackage()throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let source=directory.appendingPathComponent("download.tmp"),bytes=Data(repeating:0x53,count:1024)
        try bytes.write(to:source)
        let digest=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
        let valid=CatalogFirmware(id:"test",name:"Test",version:"1",author:"Test",url:"https://example.invalid/firmware",sha256:digest,source:"https://example.invalid",size:bytes.count,beta:false)
        let first=try valid.stageDownload(from:source),second=try valid.stageDownload(from:source)
        defer {try? FileManager.default.removeItem(at:first.deletingLastPathComponent());try? FileManager.default.removeItem(at:second.deletingLastPathComponent())}
        XCTAssertNotEqual(first,second,"Concurrent downloads must not overwrite each other's staged package")
        XCTAssertNotEqual(first.deletingLastPathComponent(),second.deletingLastPathComponent())
        XCTAssertEqual(first.lastPathComponent,valid.filename+".fwsc","The catalogue name must reach the importer without a UUID prefix")
        XCTAssertEqual(second.lastPathComponent,first.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf:first),bytes)
        try Data(repeating:0x54,count:bytes.count).write(to:source)
        XCTAssertThrowsError(try valid.stageDownload(from:source),"A same-size corrupt download must never reach the importer")
    }
}

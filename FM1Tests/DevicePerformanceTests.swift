import XCTest
import UIKit
@testable import FM1

final class DevicePerformanceTests: XCTestCase {
    @MainActor func testStockOnPhysicalDevice() throws {try measure("stock", "Stock-V15")}
    @MainActor func testFeluccaOnPhysicalDevice() throws {try measure("felucca", "Felucca-1.6.1")}
    @MainActor func testSloopOnPhysicalDevice() throws {try measure("sloop", "SLOOP-2.7.1")}
    @MainActor private func measure(_ needle:String,_ pinnedName:String) throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical-device measurement only")
        #else
        let previousIdlePolicy=UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled=true
        defer {UIApplication.shared.isIdleTimerDisabled=previousIdlePolicy}
        let instrument = Instrument()
        defer {instrument.pause()}
        let firmware = try XCTUnwrap(instrument.firmwares.first {$0.name == pinnedName || $0.name.hasPrefix(pinnedName + " · ")})
        let started=Date()
        instrument.load(firmware)
        let boot=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in instrument.running && !instrument.busy && instrument.selected?.id == firmware.id },object:nil)
        guard XCTWaiter.wait(for:[boot],timeout:20) == .completed else {XCTFail("Firmware did not start: \(firmware.name)");return}
        instrument.key(21,true)
        let play = expectation(description:"Sustained note \(needle)")
        DispatchQueue.main.asyncAfter(deadline:.now()+25) {play.fulfill()}
        wait(for:[play],timeout:30)
        instrument.key(21,false)
        instrument.pause()
        let stopped=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in !instrument.running },object:nil)
        guard XCTWaiter.wait(for:[stopped],timeout:10) == .completed else {XCTFail("Pause did not finish");return}
        let url=instrument.directory.deletingLastPathComponent().appendingPathComponent("AudioDiagnostics.json")
        let data=try Data(contentsOf:url)
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        let report=try decoder.decode(AudioDiagnostics.self,from:data)
        XCTAssertEqual(report.firmware,firmware.id)
        XCTAssertGreaterThanOrEqual(report.updatedAt.timeIntervalSince1970,started.timeIntervalSince1970.rounded(.down))
        XCTAssertGreaterThan(report.elapsedSeconds,20)
        try data.write(to:instrument.directory.deletingLastPathComponent().appendingPathComponent("Performance-\(needle).json"),options:.atomic)
        print("PHYSICAL AUDIO \(needle): \(String(decoding:data,as:UTF8.self))")
        #endif
    }
}

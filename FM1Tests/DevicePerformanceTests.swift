import XCTest
import UIKit
import CryptoKit
import Darwin
@testable import FM1

final class DevicePerformanceTests: XCTestCase {
    /// Test-only access to the matching Rust LLVM runtime, when explicitly linked.
    /// Ordinary tests never resolve symbols, reset counters or write profiles.
    @MainActor private func preparePGOProfile(_ key:String,directory:URL) throws -> (() throws -> Void)? {
        guard ProcessInfo.processInfo.environment["FM1_WRITE_LLVM_PROFILE"] == "1" else {return nil}
        guard let handle=dlopen(nil,RTLD_NOW) else {
            throw NSError(domain:"FM1PGO",code:1,userInfo:[NSLocalizedDescriptionKey:"Unable to inspect the instrumented app"])
        }
        defer {dlclose(handle)} // The main executable remains loaded for the process lifetime.
        guard let set=dlsym(handle,"__llvm_profile_set_filename"),
              let reset=dlsym(handle,"__llvm_profile_reset_counters"),
              let write=dlsym(handle,"__llvm_profile_write_file") else {
            throw NSError(domain:"FM1PGO",code:1,userInfo:[NSLocalizedDescriptionKey:"Matching LLVM profile runtime symbols are missing from the instrumented app"])
        }
        typealias SetFilename = @convention(c) (UnsafePointer<CChar>) -> Void
        typealias Reset = @convention(c) () -> Void
        typealias Write = @convention(c) () -> Int32
        let folder=directory.appendingPathComponent("PGO",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let filename=folder.appendingPathComponent("\(key)-%p.profraw").path
        filename.withCString {unsafeBitCast(set,to:SetFilename.self)($0)}
        unsafeBitCast(reset,to:Reset.self)()
        return {
            guard unsafeBitCast(write,to:Write.self)() == 0 else {
                throw NSError(domain:"FM1PGO",code:2,userInfo:[NSLocalizedDescriptionKey:"LLVM profile write failed"])
            }
        }
    }
    @MainActor func testStockOnPhysicalDevice() throws {try measure("stock", "Stock-V15")}
    @MainActor func testFeluccaOnPhysicalDevice() throws {try measure("felucca", "Felucca-1.6.1")}
    @MainActor func testSloopOnPhysicalDevice() throws {try measure("sloop", "SLOOP-2.7.1")}
    @MainActor private func measure(_ needle:String,_ pinnedName:String) throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["FM1_RUN_SIMULATOR_PERFORMANCE"] == "1" else {
            throw XCTSkip("Simulator performance is opt-in: FM1_RUN_SIMULATOR_PERFORMANCE=1")
        }
        #if DEBUG
        throw XCTSkip("Simulator performance requires a Release test build")
        #endif
        let platform="iOS Simulator"
        #else
        let platform="iOS device"
        #endif
        let previousIdlePolicy=UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled=true
        defer {UIApplication.shared.isIdleTimerDisabled=previousIdlePolicy}
        let instrument = Instrument()
        defer {instrument.pause()}
        let firmware = try XCTUnwrap(instrument.firmwares.first {$0.name == pinnedName || $0.name.hasPrefix(pinnedName + " · ")})
        let package=try Data(contentsOf:firmware.url)
        let digest=SHA256.hash(data:package).map {String(format:"%02x",$0)}.joined()
        let pinned=try XCTUnwrap(CatalogFirmware.bundled.first {$0.id == needle})
        XCTAssertEqual(digest,pinned.sha256,"Benchmark firmware must match the pinned release")
        let flashURL=firmware.url.deletingPathExtension().appendingPathExtension("flash")
        let initialFlash=(try? Data(contentsOf:flashURL)).map {SHA256.hash(data:$0).map {String(format:"%02x",$0)}.joined()}
        let writeProfile=try preparePGOProfile(needle,directory:instrument.directory.deletingLastPathComponent())
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
        var envelope=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        let environment=ProcessInfo.processInfo.environment
        envelope["benchmarkPlatform"]=platform
        envelope["benchmarkDeviceName"]=environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.model
        envelope["benchmarkModelIdentifier"]=environment["SIMULATOR_MODEL_IDENTIFIER"] ?? report.device
        envelope["benchmarkRevision"]=environment["FM1_BENCHMARK_REVISION"] ?? "unspecified"
        envelope["benchmarkRun"]=environment["FM1_BENCHMARK_RUN"] ?? "unspecified"
        envelope["benchmarkFirmwareSHA256"]=digest
        envelope["benchmarkInitialFlashSHA256"]=initialFlash ?? "absent"
        envelope["benchmarkNoteMatrixID"]=21
        envelope["benchmarkHoldSeconds"]=25
        #if DEBUG
        envelope["benchmarkConfiguration"]="Debug"
        #else
        envelope["benchmarkConfiguration"]="Release"
        #endif
        let measured=try JSONSerialization.data(withJSONObject:envelope,options:[.prettyPrinted,.sortedKeys])
        try measured.write(to:instrument.directory.deletingLastPathComponent().appendingPathComponent("Performance-\(needle).json"),options:.atomic)
        print("AUDIO BENCHMARK \(platform) \(needle): \(String(decoding:measured,as:UTF8.self))")
        try writeProfile?()
    }
}

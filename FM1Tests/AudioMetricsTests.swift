import XCTest
@testable import FM1

final class AudioMetricsTests: XCTestCase {
    func testEngineNoticesAreBundled() throws {
        for name in ["LICENSE-fm1-emu", "NOTICE-native-sloop", "LICENSE-native-sloop"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: nil), "Missing bundled notice: \(name)")
            XCTAssertGreaterThan(try String(contentsOf: url).count, 50)
        }
    }
    func testBackendDiagnosticsRoundTripAndReadLegacyReports() throws {
        var report = AudioDiagnostics()
        report.backend = .native
        report.nativeWorkload = NativeWorkloadDiagnostics(counters:[100,8,6,0,90,32000,2047,15,99,4,3,2,6,0,0,0])
        let encoded = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(AudioDiagnostics.self, from: encoded).backend, .native)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "backend")
        legacy.removeValue(forKey: "nativeWorkload")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let decodedLegacy=try JSONDecoder().decode(AudioDiagnostics.self, from: legacyData)
        XCTAssertNil(decodedLegacy.backend);XCTAssertNil(decodedLegacy.nativeWorkload)
        let roundTrip=try JSONDecoder().decode(AudioDiagnostics.self, from: encoded)
        XCTAssertEqual(roundTrip.nativeWorkload?.peakSharedSynthVoices,8)
        XCTAssertEqual(roundTrip.nativeWorkload?.peakTrackSynthVoices,[4,3,2])
        XCTAssertEqual(roundTrip.nativeWorkload?.configuredEffectMask,2047)
        XCTAssertNil(NativeWorkloadDiagnostics(counters:[0]))
        XCTAssertNil(AudioBackend(coreCode: 0))
        XCTAssertEqual(AudioBackend(coreCode: 1), .interpreter)
        XCTAssertEqual(AudioBackend(coreCode: 2), .native)
    }
    func testActualAudioBudgetAndMissingFramesAreMeasuredSeparately() {
        var health = AudioHealth()
        health.record(renderSeconds: 0.01, validFrames: 441, frames: 441)
        health.record(renderSeconds: 0.02, validFrames: 220, frames: 441)
        let report = health.diagnostics(elapsed: 2)
        XCTAssertEqual(report.renderRatioMean, 1.5, accuracy: 0.0001)
        XCTAssertEqual(report.renderRatioP95, 2, accuracy: 0.0001)
        XCTAssertEqual(report.renderRatioMax, 2, accuracy: 0.0001)
        XCTAssertEqual(report.renderedFrames, 661)
        XCTAssertEqual(report.missingFrames, 221)
        XCTAssertEqual(report.estimatedQueueGaps, 0)
    }
    func testRecentPercentileRecoversWhileMaximumAndTotalsRemain() {
        var health = AudioHealth()
        health.record(renderSeconds: 1, validFrames: 441, frames: 441)
        for _ in 0..<256 { health.record(renderSeconds: 0.005, validFrames: 441, frames: 441) }
        health.recordGap(seconds: 0.02); health.recordGap(seconds: 0.01)
        let report = health.diagnostics(elapsed: 4)
        XCTAssertEqual(report.renderRatioP95, 0.5, accuracy: 0.0001)
        XCTAssertEqual(report.renderRatioMax, 100, accuracy: 0.0001)
        XCTAssertEqual(report.estimatedQueueGaps, 2)
        XCTAssertEqual(report.estimatedGapSeconds, 0.03, accuracy: 0.0001)
        XCTAssertEqual(report.largestEstimatedGapSeconds, 0.02)
    }
    func testCompleteAudioIsUnchangedAndMissingTailIsSmooth() {
        var smoother = AudioGapSmoother()
        let original = (0..<1024).map { Float($0 % 11) / 11 }
        var samples = original
        smoother.process(&samples, validFrames: 512, frames: 512)
        XCTAssertEqual(samples, original)
        samples = [Float](repeating: 1, count: 1024)
        smoother.process(&samples, validFrames: 400, frames: 512)
        XCTAssertEqual(samples[798], 1)
        XCTAssertGreaterThan(samples[800], 0.9)
        XCTAssertEqual(samples[926], 0)
        XCTAssertEqual(samples[1023], 0)
        samples = [Float](repeating: 1, count: 1024)
        smoother.process(&samples, validFrames: 512, frames: 512)
        XCTAssertLessThan(samples[0], 0.02)
        XCTAssertEqual(samples[126], 1)
        XCTAssertEqual(samples[1023], 1)
    }
}

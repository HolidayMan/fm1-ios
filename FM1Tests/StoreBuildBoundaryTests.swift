import XCTest
@testable import FM1

final class StoreBuildBoundaryTests:XCTestCase {
    func testHostAndCoreBuildPoliciesMatch() {
        #if FM1_RESEARCH
        XCTAssertTrue(instrument_research_enabled())
        #else
        XCTAssertFalse(instrument_research_enabled())
        let model=Instrument(nativeOnly:false)
        XCTAssertTrue(model.nativeOnly,"Store builds cannot opt into research execution")
        XCTAssertFalse(model.supportsExperimentalWASM)
        #endif
    }
    #if !FM1_RESEARCH
    func testCompiledBundleContainsNoResearchExecutionResources()throws {
        let resources=try XCTUnwrap(Bundle.main.resourceURL)
        let paths=try XCTUnwrap(FileManager.default.enumerator(at:resources,includingPropertiesForKeys:nil))
        for case let path as URL in paths {
            XCTAssertFalse(["wasm","js","html","fwsc"].contains(path.pathExtension.lowercased()),path.lastPathComponent)
        }
        XCTAssertNotNil(Bundle.main.url(forResource:"PrivacyInfo",withExtension:"xcprivacy"))
    }
    #endif
}

import XCTest
@testable import FM1

/// Opt-in reproduction on a private read-only device copy. Each run forks that
/// fixture again; neither the phone nor the preserved copy is ever opened by an engine.
@MainActor final class OwnerWorkspaceStartupTests:XCTestCase {
    private func wait(_ model:Instrument,running:Bool)async throws {
        let until=ProcessInfo.processInfo.systemUptime+20
        while model.busy || model.running != running {
            guard ProcessInfo.processInfo.systemUptime<until else {
                XCTFail("The isolated native workspace did not settle")
                throw ProjectFilesError("Startup did not settle")
            }
            try await Task.sleep(nanoseconds:20_000_000)
        }
    }
    private func reproduce(previousVersion:Bool)async throws {
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let source=documents.appendingPathComponent("PerformanceFixtures/OwnerStartup27")
        guard FileManager.default.fileExists(atPath:source.appendingPathComponent("preferences.plist").path) else {throw XCTSkip("Requires the explicitly staged private read-only workspace copy")}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at:source.appendingPathComponent("Firmwares"),to:root)
        let preferencesData=try Data(contentsOf:source.appendingPathComponent("preferences.plist"))
        let values=try XCTUnwrap(PropertyListSerialization.propertyList(from:preferencesData,format:nil) as? [String:Any])
        let suite="OwnerWorkspaceStartup.\(UUID().uuidString)",preferences=UserDefaults(suiteName:suite)!
        for key in [FirmwareSelection.preferenceKey,SloopExecutionMode.preferenceKey] {if let value=values[key] {preferences.set(value,forKey:key)}}
        if previousVersion {
            // Exercise only the supported 2.7.1 -> 2.8 migration on a fresh fork.
            // The real preserved 2.8 save remains present in the source copy.
            let id=try XCTUnwrap(preferences.string(forKey:FirmwareSelection.preferenceKey))
            try FileManager.default.removeItem(at:root.appendingPathComponent(id).appendingPathExtension("flash"))
        }
        let worker=DispatchQueue(label:"OwnerWorkspaceStartup.worker")
        let model=Instrument(directory:root,preferences:preferences,worker:worker,nativeOnly:true)
        defer {
            model.pause()
            preferences.removePersistentDomain(forName:suite)
            // Worker FIFO drains checkpoint before deleting its temporary branch.
            worker.async {try? FileManager.default.removeItem(at:root)}
        }
        let until=ProcessInfo.processInfo.systemUptime+15
        while model.selected == nil {
            guard ProcessInfo.processInfo.systemUptime<until else {XCTFail("The copied installed firmware was not discovered");return}
            try await Task.sleep(nanoseconds:20_000_000)
        }
        model.sceneChanged(active:true)
        try await wait(model,running:true)
        XCTAssertNil(model.message)
        XCTAssertEqual(model.nativeBackendName,"SLOOP")
        XCTAssertTrue(model.supportsProjectFiles)
        model.pause();try await wait(model,running:false)
        let saved=try await model.captureSloopExportContext()
        XCTAssertEqual(saved.snapshot.packageSHA256,SloopExecutionMode.packageSHA256)
        XCTAssertTrue(model.load(try XCTUnwrap(model.selected)))
        try await wait(model,running:true)
        XCTAssertNil(model.message)
        model.pause();try await wait(model,running:false)
    }
    func testActualCopiedNativeWorkspaceStartsAndReloads()async throws {try await reproduce(previousVersion:false)}
    func testCopiedPreviousVersionWorkspaceMigratesAndStarts()async throws {try await reproduce(previousVersion:true)}
}

import XCTest
@testable import FM1

/// Only the pinned package is read from Documents. Engines, preferences, project
/// files and automatic saves all belong to a fresh temporary fixture.
@MainActor final class ProjectFilesIntegrationTests:XCTestCase {
    private struct Fixture {
        let model:Instrument
        let store:ProjectFilesStore
        let root:URL
        let preferences:UserDefaults
        let suite:String
    }

    private func package()throws->Data {
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        for folder in ["Native16Packages","Native13Packages","Firmwares"] {
            for url in (try? FileManager.default.contentsOfDirectory(at:documents.appendingPathComponent(folder),includingPropertiesForKeys:nil)) ?? [] where url.pathExtension == "fwsc" {
                let bytes=try Data(contentsOf:url)
                if bytes.withUnsafeBytes({instrument_native_kind_for_fwsc($0.bindMemory(to:UInt8.self).baseAddress,bytes.count)}) == 2 {return bytes}
            }
        }
        throw XCTSkip("Requires the pinned local SLOOP package; never downloads or reads owner saves")
    }

    private func waitUntil(_ description:String,file:StaticString=#filePath,line:UInt=#line,_ ready:()->Bool)async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+20
        while !ready() {
            guard ProcessInfo.processInfo.systemUptime<deadline else {
                XCTFail(description,file:file,line:line)
                throw ProjectFilesError(description)
            }
            // Yield MainActor so discovery and playback completion can publish.
            try await Task.sleep(nanoseconds:20_000_000)
        }
    }

    private func settle(_ model:Instrument,running:Bool,file:StaticString=#filePath,line:UInt=#line)async throws {
        try await waitUntil("The isolated instrument did not settle: \(model.status), \(model.message ?? "no error")",file:file,line:line) {
            !model.busy && model.running == running
        }
    }

    private func fixture()async throws->Fixture {
        let bytes=try package()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("ProjectFilesIntegration-\(UUID().uuidString)",isDirectory:true)
        let firmwares=root.appendingPathComponent("Firmwares",isDirectory:true)
        try FileManager.default.createDirectory(at:firmwares,withIntermediateDirectories:true)
        try bytes.write(to:firmwares.appendingPathComponent("SLOOP-2.7.1.fwsc"))
        let suite="ProjectFilesIntegration.\(UUID().uuidString)"
        let preferences=try XCTUnwrap(UserDefaults(suiteName:suite))
        let model=Instrument(directory:firmwares,preferences:preferences,nativeOnly:true)
        let fixture=Fixture(model:model,store:ProjectFilesStore(instrument:model,directory:root.appendingPathComponent("Projects",isDirectory:true)),root:root,preferences:preferences,suite:suite)
        do {
            try await waitUntil("The isolated SLOOP fixture was not discovered.") {!model.firmwares.isEmpty}
            model.load(try XCTUnwrap(model.firmwares.first))
            try await settle(model,running:true)
            XCTAssertNil(model.message)
            model.pause();try await settle(model,running:false)
            return fixture
        } catch {await cleanup(fixture);throw error}
    }

    private func cleanup(_ fixture:Fixture)async {
        fixture.model.pause()
        try? await settle(fixture.model,running:false)
        fixture.preferences.removePersistentDomain(forName:fixture.suite)
        try? FileManager.default.removeItem(at:fixture.root)
    }

    private func sample()throws->Data {
        let source=SampleAudioSource(name:"Integration tone",samples:(0..<2205).map {Float(sin(Double($0)*0.13)*0.3)},sourceRate:22050,sourceChannels:1)
        return try SampleAudioImporter.encode(source:source,start:0,end:source.duration)
    }

    private func replacing(_ snapshot:SloopWorkSnapshot,name:String,bytes:Data,master:UInt32?=nil)->SloopWorkSnapshot {
        SloopWorkSnapshot(version:snapshot.version,packageSHA256:snapshot.packageSHA256,master:master ?? snapshot.master,parts:snapshot.parts.map {$0.name == name ? .init(name,bytes) : $0})
    }

    private func assertSameWork(_ actual:SloopWorkSnapshot,_ expected:SloopWorkSnapshot,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(actual.master,expected.master,file:file,line:line)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues:actual.parts.map {($0.name,$0.bytes)}),Dictionary(uniqueKeysWithValues:expected.parts.map {($0.name,$0.bytes)}),file:file,line:line)
    }

    func testNamedProjectRestoresSampleAndPreservesCurrentGlobalSettings()async throws {
        let f=try await fixture()
        addTeardownBlock { @MainActor in await self.cleanup(f) }
        let original=try await f.model.captureSloopExportContext().snapshot
        await f.store.saveCurrent(name:"Original sample project")
        XCTAssertNil(f.store.errorMessage)
        let named=try XCTUnwrap(f.store.items.first(where:{$0.kind == .project}))
        let namedBytes=try Data(contentsOf:named.url)
        let envelope=try ProjectFileEnvelope.read(named.url)
        XCTAssertEqual(envelope.name,"Original sample project")
        XCTAssertEqual(try envelope.snapshot.bytes("sample0"),try original.bytes("sample0"))

        // Change a real global setting after saving the musical project. PER3
        // lowcut is a UInt32 at offset8; this avoids a vacuous defaults-only check.
        var settings=try original.bytes("object1")
        XCTAssertGreaterThanOrEqual(settings.count,16)
        guard settings.count>=16 else {throw ProjectFilesError("Missing source settings fixture")}
        settings[8]=settings[8] == 0 ? 1 : 0
        let customized=replacing(original,name:"object1",bytes:settings,master:271)
        try await f.model.replaceSloopWork(customized,kind:.backup,recoveryURL:f.root.appendingPathComponent("Before-custom-settings.fm1backup"))
        let globals=try await f.model.captureSloopExportContext().snapshot
        XCTAssertNotEqual(try globals.bytes("object1"),try original.bytes("object1"))
        XCTAssertEqual(globals.master,271)

        let encoded=try sample()
        XCTAssertEqual(encoded.count,81920)
        XCTAssertEqual(encoded.prefix(4),Data("FSMP".utf8))
        XCTAssertNotEqual(encoded,try original.bytes("sample0"))
        try await f.store.importSample(slotData:encoded,slot:0,name:"Integration tone")
        let imported=try await f.model.captureSloopExportContext().snapshot
        XCTAssertEqual(try imported.bytes("sample0"),encoded)
        XCTAssertEqual(imported.master,globals.master)
        for name in ["object1","object10","object11"] {XCTAssertEqual(try imported.bytes(name),try globals.bytes(name),name)}

        await f.store.open(named)
        XCTAssertNil(f.store.errorMessage)
        let reopened=try await f.model.captureSloopExportContext().snapshot
        XCTAssertEqual(try reopened.bytes("sample0"),try original.bytes("sample0"))
        XCTAssertEqual(reopened.master,globals.master)
        for name in ["object1","object10","object11"] {XCTAssertEqual(try reopened.bytes(name),try globals.bytes(name),name)}
        XCTAssertEqual(try Data(contentsOf:named.url),namedBytes,"Opening must not rewrite a manually named project")

        let recoveries=try f.store.items.filter{$0.kind == .backup}.map {try ProjectFileEnvelope.read($0.url).snapshot}
        XCTAssertGreaterThanOrEqual(recoveries.count,2)
        XCTAssertTrue(try recoveries.contains {try $0.bytes("sample0") == encoded},"Recovery before opening must retain the replaced sound")
        XCTAssertTrue(try recoveries.contains {try $0.bytes("sample0") == original.bytes("sample0")},"Recovery before sample import must retain the previous slot")

        f.model.load(try XCTUnwrap(f.model.selected));try await settle(f.model,running:true)
        f.model.pause();try await settle(f.model,running:false)
        let durable=try await f.model.captureSloopExportContext().snapshot
        XCTAssertEqual(try durable.bytes("sample0"),try original.bytes("sample0"))
        XCTAssertEqual(try durable.bytes("object1"),try globals.bytes("object1"))
        XCTAssertEqual(durable.master,globals.master)
    }

    func testRecoveryWriteFailureKeepsCurrentWorkSaveAndPlayback()async throws {
        let f=try await fixture()
        addTeardownBlock { @MainActor in await self.cleanup(f) }
        f.model.resume();try await settle(f.model,running:true)
        let before=try await f.model.captureSloopExportContext().snapshot
        let flash=try XCTUnwrap(f.model.selected).url.deletingPathExtension().appendingPathExtension("flash")
        let persisted=try Data(contentsOf:flash)
        let selected=f.model.selected
        let blocker=f.root.appendingPathComponent("Regular-file-not-directory")
        let sentinel=Data("Keep this existing file".utf8)
        try sentinel.write(to:blocker)
        let candidate=try before.replacingSample(sample(),slot:0)
        var replacementError:NSError?
        do {
            try await f.model.replaceSloopWork(candidate,kind:.backup,recoveryURL:blocker.appendingPathComponent("Recovery.fm1backup"))
            XCTFail("Replacing without a durable recovery backup must fail")
        } catch {
            replacementError=error as NSError
        }
        let failure=try XCTUnwrap(replacementError)
        XCTAssertEqual(failure.domain,NSCocoaErrorDomain,"Exercise the recovery filesystem failure, not an earlier candidate rejection: \(failure)")
        try await settle(f.model,running:true)
        XCTAssertEqual(f.model.selected,selected)
        XCTAssertNil(f.model.message)
        assertSameWork(try await f.model.captureSloopExportContext().snapshot,before)
        XCTAssertEqual(try Data(contentsOf:flash),persisted)
        XCTAssertEqual(try Data(contentsOf:blocker),sentinel)
        XCTAssertTrue(f.store.items.isEmpty)
    }

    func testChecksumCorruptImportLeavesWorkspaceAndLibraryUntouched()async throws {
        let f=try await fixture()
        addTeardownBlock { @MainActor in await self.cleanup(f) }
        let before=try await f.model.captureSloopExportContext().snapshot
        let selected=f.model.selected
        let flash=try XCTUnwrap(selected).url.deletingPathExtension().appendingPathExtension("flash")
        let persisted=try Data(contentsOf:flash)
        let envelope=ProjectFileEnvelope(name:"Corrupted external project",kind:.project,snapshot:before)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:envelope.encoded()) as? [String:Any])
        var parts=try XCTUnwrap(json["snapshot"] as? [String:Any])
        var components=try XCTUnwrap(parts["parts"] as? [[String:Any]])
        let index=try XCTUnwrap(components.firstIndex(where:{$0["name"] as? String == "sample0"}))
        var damaged=try before.bytes("sample0");damaged[512] ^= 1
        components[index]["bytes"]=damaged.base64EncodedString() // Keep the original checksum.
        parts["parts"]=components;json["snapshot"]=parts
        let bytes=try JSONSerialization.data(withJSONObject:json)
        let external=f.root.appendingPathComponent("External.fm1project")
        try bytes.write(to:external)

        await f.store.importFile(external)
        XCTAssertTrue(f.store.errorMessage?.contains("checksum") == true,"The intact envelope must be rejected specifically for component integrity")
        XCTAssertFalse(f.model.running)
        XCTAssertFalse(f.model.busy)
        XCTAssertEqual(f.model.selected,selected)
        assertSameWork(try await f.model.captureSloopExportContext().snapshot,before)
        XCTAssertEqual(try Data(contentsOf:flash),persisted)
        XCTAssertEqual(try Data(contentsOf:external),bytes)
        await f.store.refresh()
        XCTAssertTrue(f.store.items.isEmpty,"Rejected content must create neither a project copy nor a recovery backup")
    }
}

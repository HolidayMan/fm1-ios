import XCTest
@testable import FM1

@MainActor final class ProjectFileFormatTests:XCTestCase {
    private func snapshot(marker:UInt8)->SloopWorkSnapshot {
        var parts=[SloopWorkSnapshot.Part("flash",Data(repeating:marker,count:1<<20)),SloopWorkSnapshot.Part("arrangement",Data([0,0,0,0,0,0,0,0,0,0,1,0,1]))]
        parts += (0..<12).map{SloopWorkSnapshot.Part("object\($0)",Data([marker,UInt8($0)]))}
        parts += (0..<4).map{SloopWorkSnapshot.Part("sample\($0)",Data(repeating:255,count:81920))}
        return SloopWorkSnapshot(version:1,packageSHA256:SloopExecutionMode.packageSHA256,master:UInt32(marker),parts:parts)
    }
    func testPreviousReleaseSnapshotOpensAsCopyWithCurrentProjectIdentity()throws {
        let current=snapshot(marker:12),old=snapshot(marker:34)
        let previous=SloopWorkSnapshot(version:old.version,packageSHA256:SloopVersionMigration.previousPackageSHA256,master:old.master,parts:old.parts)
        try previous.validate()
        let original=try JSONEncoder().encode(previous)
        let opened=try previous.projectOverlay(on:current)
        XCTAssertEqual(opened.packageSHA256,SloopExecutionMode.packageSHA256)
        XCTAssertEqual(try opened.bytes("object0"),try previous.bytes("object0"))
        XCTAssertEqual(try JSONEncoder().encode(previous).count,original.count)
        XCTAssertEqual(previous.packageSHA256,SloopVersionMigration.previousPackageSHA256)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("Previous.fm1project")
        try ProjectFileEnvelope(name:"Previous",kind:.project,snapshot:previous).encoded().write(to:file)
        XCTAssertEqual(try ProjectFileEnvelope.read(file).snapshot.packageSHA256,SloopVersionMigration.previousPackageSHA256)
    }
    func testLegacyWorkspaceCopyUsesVerifiedPackageAndPreservesSource()throws {
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let package=documents.appendingPathComponent("Previous27MigrationPackages/SLOOP-2.7.1.fwsc")
        guard FileManager.default.fileExists(atPath:package.path) else {throw XCTSkip("Requires the isolated predecessor package fixture")}
        let bytes=try Data(contentsOf:package)
        XCTAssertEqual(SloopWorkSnapshot.digest(bytes),SloopVersionMigration.previousPackageSHA256)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        for (id,marker) in [("Previous A",UInt8(17)),("Previous B",UInt8(29))] {
            try bytes.write(to:folder.appendingPathComponent(id).appendingPathExtension("fwsc"))
            try Data(repeating:marker,count:1<<20).write(to:folder.appendingPathComponent(id).appendingPathExtension("flash"))
        }
        XCTAssertThrowsError(try SloopVersionMigration.previousWorkspace(in:folder,preferredID:nil))
        let source=folder.appendingPathComponent("Previous A.flash"),original=try Data(contentsOf:source)
        let copied=try XCTUnwrap(SloopVersionMigration.previousWorkspace(in:folder,preferredID:"Previous A"))
        XCTAssertEqual(copied,original)
        XCTAssertEqual(try Data(contentsOf:source),original)
        try Data([1,2]).write(to:source)
        XCTAssertThrowsError(try SloopVersionMigration.previousWorkspace(in:folder,preferredID:"Previous A"))
    }
    func testLegacyWorkspaceDiscoveryRejectsUnverifiedPackages()throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        try Data(repeating:0,count:1000).write(to:folder.appendingPathComponent("SLOOP-2.7.1.fwsc"))
        try Data(repeating:17,count:1<<20).write(to:folder.appendingPathComponent("SLOOP-2.7.1.flash"))
        XCTAssertNil(try SloopVersionMigration.previousWorkspace(in:folder,preferredID:"SLOOP-2.7.1"))
    }
    func testProjectOverlayPreservesUnrelatedWorkspaceAndMaster()throws {
        let current=snapshot(marker:12),incoming=snapshot(marker:34)
        let result=try incoming.projectOverlay(on:current)
        XCTAssertEqual(result.master,current.master)
        for name in ["flash","object1","object10","object11"] {XCTAssertEqual(try result.bytes(name),try current.bytes(name),name)}
        for name in ["object0","object2","object3","object4","object5","object6","object7","object8","object9","arrangement","sample0","sample1","sample2","sample3"] {XCTAssertEqual(try result.bytes(name),try incoming.bytes(name),name)}
    }
    func testFormatRejectsChecksumDamageDuplicateMissingAndWrongVersion()throws {
        let valid=snapshot(marker:22);try valid.validate()
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(valid)) as? [String:Any])
        var parts=try XCTUnwrap(json["parts"] as? [[String:Any]])
        parts[0]["bytes"]=Data([1,2,3]).base64EncodedString();json["parts"]=parts
        let broken=try JSONDecoder().decode(SloopWorkSnapshot.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertThrowsError(try broken.validate())
        let duplicate=SloopWorkSnapshot(version:1,packageSHA256:valid.packageSHA256,master:valid.master,parts:Array(valid.parts.dropLast())+[valid.parts[0]])
        XCTAssertThrowsError(try duplicate.validate())
        XCTAssertThrowsError(try SloopWorkSnapshot(version:99,packageSHA256:valid.packageSHA256,master:1,parts:valid.parts).validate())
        XCTAssertThrowsError(try SloopWorkSnapshot(version:1,packageSHA256:String(repeating:"0",count:64),master:1,parts:valid.parts).validate())
        XCTAssertThrowsError(try valid.replacingSample(Data([1]),slot:0))
        XCTAssertThrowsError(try valid.replacingSample(Data(count:81920),slot:4))
    }
    func testSharedProjectScrubsPrivateWorkspaceAndBackupPreservesIt()throws {
        let current=snapshot(marker:71)
        let project=ProjectFileEnvelope(name:"Share me",kind:.project,snapshot:current)
        let decoded=try JSONDecoder().decode(ProjectFileEnvelope.self,from:project.encoded())
        XCTAssertEqual(try decoded.snapshot.bytes("flash"),Data(repeating:255,count:1<<20))
        for name in ["object1","object10","object11"] {XCTAssertTrue(try decoded.snapshot.bytes(name).isEmpty)}
        for name in ["object0","object2","object9","sample0"] {XCTAssertEqual(try decoded.snapshot.bytes(name),try current.bytes(name))}
        let opened=try decoded.snapshot.projectOverlay(on:current)
        for name in ["flash","object1","object10","object11"] {XCTAssertEqual(try opened.bytes(name),try current.bytes(name))}
        let backup=ProjectFileEnvelope(name:"Private backup",kind:.backup,snapshot:current)
        let restored=try JSONDecoder().decode(ProjectFileEnvelope.self,from:backup.encoded())
        for part in current.parts {XCTAssertEqual(try restored.snapshot.bytes(part.name),part.bytes)}
    }
    func testProjectAndBackupLabelsCannotBeInterchanged()throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let envelope=ProjectFileEnvelope(name:"A piece",kind:.project,snapshot:snapshot(marker:22))
        let correct=folder.appendingPathComponent("A piece.fm1project"),wrong=folder.appendingPathComponent("A piece.fm1backup")
        try envelope.encoded().write(to:correct);try envelope.encoded().write(to:wrong)
        XCTAssertEqual(try ProjectFileEnvelope.read(correct).name,"A piece")
        XCTAssertThrowsError(try ProjectFileEnvelope.read(wrong))
    }
    func testDefaultLibraryIsOwnedByItsExactInstrumentWorkspace() {
        let base=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:base)}
        for name in ["Firmwares","Glass17Fixture","PerformanceFixtures"] {
            let directory=base.appendingPathComponent(name)
            let instrument=Instrument(directory:directory,nativeOnly:true)
            let store=ProjectFilesStore(instrument:instrument)
            XCTAssertEqual(store.directory,directory.appendingPathComponent("Projects",isDirectory:true))
            XCTAssertNotEqual(store.directory,base.appendingPathComponent("Projects",isDirectory:true))
        }
    }
    func testImportInspectionStagesIndependentCopyWithoutOpening()async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let source=folder.appendingPathComponent("External.fm1project")
        let e=ProjectFileEnvelope(name:"External piece",kind:.project,snapshot:snapshot(marker:5));try e.encoded().write(to:source)
        let instrument=Instrument(directory:folder.appendingPathComponent("Firmwares"),nativeOnly:true)
        let store=ProjectFilesStore(instrument:instrument,directory:folder.appendingPathComponent("Projects"))
        let preview=try await store.inspectImport(source)
        XCTAssertEqual(preview.name,"External piece");XCTAssertFalse(preview.canOpen)
        XCTAssertNil(instrument.selected);XCTAssertFalse(instrument.running)
        try FileManager.default.removeItem(at:source)
        XCTAssertEqual(try ProjectFileEnvelope.read(preview.stagedURL).name,"External piece")
        XCTAssertTrue(store.items.isEmpty)
        store.discardStagedImport(preview.stagedURL)
    }
}

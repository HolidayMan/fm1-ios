import XCTest
@testable import FM1

/// Files and musical payloads are synthetic and belong to one temporary root.
/// These tests need no package, live audio, user library or device data.
@MainActor final class ProjectFilesDeletionTests:XCTestCase {
    private var root:URL!
    private var library:URL!
    private var instrument:Instrument!
    private var store:ProjectFilesStore!
    private var preferences:UserDefaults!
    private var suite:String!

    override func setUp()async throws {
        root=FileManager.default.temporaryDirectory.appendingPathComponent("BackupFiles-\(UUID().uuidString)",isDirectory:true)
        library=root.appendingPathComponent("Projects",isDirectory:true)
        try FileManager.default.createDirectory(at:library,withIntermediateDirectories:true)
        suite="BackupFiles.\(UUID().uuidString)";preferences=try XCTUnwrap(UserDefaults(suiteName:suite))
        instrument=Instrument(directory:root.appendingPathComponent("Firmwares"),preferences:preferences,nativeOnly:true)
        store=ProjectFilesStore(instrument:instrument,directory:library)
    }
    override func tearDown()async throws {
        preferences?.removePersistentDomain(forName:suite)
        if let root {try? FileManager.default.removeItem(at:root)}
        store=nil;instrument=nil;preferences=nil
    }
    private func snapshot(_ marker:UInt8=31)->SloopWorkSnapshot {
        var parts=[SloopWorkSnapshot.Part("flash",Data(repeating:marker,count:1<<20)),
                   SloopWorkSnapshot.Part("arrangement",Data([0,0,0,0,0,0,0,0,0,0,1,0,1]))]
        parts += (0..<12).map{.init("object\($0)",Data([marker,UInt8($0)]))}
        parts += (0..<4).map{.init("sample\($0)",Data(repeating:255,count:81920))}
        return SloopWorkSnapshot(version:1,packageSHA256:SloopExecutionMode.packageSHA256,master:UInt32(marker),parts:parts)
    }
    private func save(_ name:String,kind:ProjectFileKind = .backup,directory:URL?=nil)throws->ProjectFileItem {
        let envelope=ProjectFileEnvelope(name:name,kind:kind,snapshot:snapshot())
        let url=(directory ?? library!).appendingPathComponent(envelope.id.uuidString).appendingPathExtension(kind == .backup ? "fm1backup" : "fm1project")
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try envelope.encoded().write(to:url)
        return ProjectFileItem(id:envelope.id,name:name,createdAt:envelope.createdAt,kind:kind,url:url)
    }
    private func assertUnloaded(file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertNil(instrument.selected,file:file,line:line)
        XCTAssertFalse(instrument.running,file:file,line:line)
        XCTAssertFalse(instrument.busy,file:file,line:line)
    }
    func testDeleteAndUndoPreserveExactBackupProjectsAndAutosave()async throws {
        let backup=try save("Current complete workspace"),project=try save("Named music",kind:.project),recovery=try save("Recovery before replacement")
        let original=try Data(contentsOf:backup.url),projectBytes=try Data(contentsOf:project.url),recoveryBytes=try Data(contentsOf:recovery.url)
        let autosave=instrument.directory.appendingPathComponent("SLOOP.flash"),sentinel=Data("Unrelated current automatic save".utf8)
        try sentinel.write(to:autosave)
        await store.refresh();XCTAssertEqual(store.items.count,3)
        await store.deleteBackup(backup)
        XCTAssertNil(store.errorMessage);XCTAssertFalse(FileManager.default.fileExists(atPath:backup.url.path))
        XCTAssertEqual(Set(store.items.map(\.id)),Set([project.id,recovery.id]))
        let deleted=try XCTUnwrap(store.recentlyDeletedBackup)
        XCTAssertEqual(deleted.id,backup.id);XCTAssertEqual(try Data(contentsOf:deleted.url),original)
        XCTAssertEqual(try Data(contentsOf:project.url),projectBytes);XCTAssertEqual(try Data(contentsOf:recovery.url),recoveryBytes)
        XCTAssertEqual(try Data(contentsOf:autosave),sentinel);assertUnloaded()
        await store.restoreDeletedBackup()
        XCTAssertNil(store.errorMessage);XCTAssertNil(store.recentlyDeletedBackup)
        XCTAssertEqual(try Data(contentsOf:backup.url),original);XCTAssertEqual(store.items.count,3);assertUnloaded()
    }
    func testUndoSurvivesRestartAndNeverOverwritesCollision()async throws {
        let backup=try save("Manual backup"),original=try Data(contentsOf:backup.url)
        await store.deleteBackup(backup);XCTAssertNil(store.errorMessage)
        let restarted=ProjectFilesStore(instrument:instrument,directory:library)
        await restarted.refresh();let deleted=try XCTUnwrap(restarted.recentlyDeletedBackup)
        XCTAssertEqual(deleted.id,backup.id)
        let collision=Data("A different file created after deletion".utf8)
        try collision.write(to:backup.url)
        await restarted.restoreDeletedBackup()
        XCTAssertNotNil(restarted.errorMessage)
        XCTAssertEqual(try Data(contentsOf:backup.url),collision)
        XCTAssertEqual(try Data(contentsOf:deleted.url),original)
        XCTAssertEqual(restarted.recentlyDeletedBackup?.id,backup.id)
        try FileManager.default.removeItem(at:backup.url)
        await restarted.restoreDeletedBackup()
        XCTAssertNil(restarted.errorMessage);XCTAssertNil(restarted.recentlyDeletedBackup)
        XCTAssertEqual(try Data(contentsOf:backup.url),original)
    }
    func testManualAndRecoveryBackupsUndoIndependentlyAfterRestart()async throws {
        let manual=try save("Complete workspace backup"),recovery=try save("Recovery before replacement")
        let first=try Data(contentsOf:manual.url),second=try Data(contentsOf:recovery.url)
        await store.deleteBackup(manual);await store.deleteBackup(recovery)
        let restarted=ProjectFilesStore(instrument:instrument,directory:library)
        await restarted.refresh();XCTAssertEqual(restarted.recentlyDeletedBackup?.id,recovery.id)
        await restarted.restoreDeletedBackup();XCTAssertEqual(try Data(contentsOf:recovery.url),second)
        XCTAssertEqual(restarted.recentlyDeletedBackup?.id,manual.id)
        await restarted.restoreDeletedBackup();XCTAssertEqual(try Data(contentsOf:manual.url),first)
        XCTAssertNil(restarted.recentlyDeletedBackup);XCTAssertEqual(restarted.items.count,2)
    }
    func testUndoDoesNotReplaceADanglingSymlinkCollision()async throws {
        let backup=try save("Do not overwrite a link"),original=try Data(contentsOf:backup.url)
        await store.deleteBackup(backup)
        let deleted=try XCTUnwrap(store.recentlyDeletedBackup)
        let missing=root.appendingPathComponent("Missing external target")
        try FileManager.default.createSymbolicLink(at:backup.url,withDestinationURL:missing)
        await store.restoreDeletedBackup()
        XCTAssertNotNil(store.errorMessage)
        // URL retains the original regular file's cached resource values after
        // deletion. Read the current directory entry, including its exact link.
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath:backup.url.path),missing.path)
        XCTAssertEqual(try URL(fileURLWithPath:backup.url.path).resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink,true)
        XCTAssertEqual(try Data(contentsOf:deleted.url),original)
        XCTAssertFalse(FileManager.default.fileExists(atPath:missing.path))
    }
    func testDeletionRejectsProjectsExternalStagedStaleAndLinkedFiles()async throws {
        let project=try save("Keep my music",kind:.project)
        let external=try save("Outside library",directory:root.appendingPathComponent("External"))
        let staged=try save("Import review",directory:library.appendingPathComponent("Staging"))
        for item in [project,external,staged] {
            let before=try Data(contentsOf:item.url)
            await store.deleteBackup(item)
            XCTAssertNotNil(store.errorMessage);XCTAssertEqual(try Data(contentsOf:item.url),before)
        }
        let backup=try save("Changed identity")
        let stale=ProjectFileItem(id:UUID(),name:backup.name,createdAt:backup.createdAt,kind:.backup,url:backup.url)
        let bytes=try Data(contentsOf:backup.url)
        await store.deleteBackup(stale);XCTAssertNotNil(store.errorMessage);XCTAssertEqual(try Data(contentsOf:backup.url),bytes)
        let link=library.appendingPathComponent("Linked.fm1backup")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:external.url)
        let linked=ProjectFileItem(id:external.id,name:external.name,createdAt:external.createdAt,kind:.backup,url:link)
        await store.deleteBackup(linked);XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try Data(contentsOf:external.url),try ProjectFileEnvelope.read(external.url).encoded())
        await store.refresh();XCTAssertFalse(store.items.contains{$0.url == link});assertUnloaded()
    }
    func testTrashLinkCannotRedirectDeletionOutsideLibrary()async throws {
        let backup=try save("Preserve source"),before=try Data(contentsOf:backup.url)
        let outside=root.appendingPathComponent("Outside",isDirectory:true)
        try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:library.appendingPathComponent(".DeletedBackups"),withDestinationURL:outside)
        await store.deleteBackup(backup)
        XCTAssertNotNil(store.errorMessage);XCTAssertEqual(try Data(contentsOf:backup.url),before)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:outside.path).isEmpty)
    }
    func testStagingLinkCannotRedirectInspectionOrCleanup()async throws {
        let external=try save("Keep external source",directory:root.appendingPathComponent("External"))
        let outside=root.appendingPathComponent("Outside",isDirectory:true)
        try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
        let sentinel=outside.appendingPathComponent("Keep.fm1backup"),bytes=Data("Outside staging sentinel".utf8)
        try bytes.write(to:sentinel)
        let staging=library.appendingPathComponent("Staging",isDirectory:true)
        try FileManager.default.createSymbolicLink(at:staging,withDestinationURL:outside)
        do {_ = try await store.inspectImport(external.url);XCTFail("Linked staging must be rejected")}catch {}
        store.discardStagedImport(staging.appendingPathComponent("Keep.fm1backup"))
        await store.refresh() // Flush the store's serial IO queue after cleanup.
        XCTAssertEqual(try Data(contentsOf:sentinel),bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:outside.path),["Keep.fm1backup"])
        assertUnloaded()
    }
    func testExportCreatesIndependentReadableCopiesAndScrubsOnlyProjectScope()async throws {
        let project=try save("Music / named copy",kind:.project),backup=try save("Complete backup")
        let projectBytes=try Data(contentsOf:project.url),backupBytes=try Data(contentsOf:backup.url)
        let sharedProject=try await store.exportFile(project),sharedBackup=try await store.exportFile(backup)
        defer {try? FileManager.default.removeItem(at:sharedProject.deletingLastPathComponent());try? FileManager.default.removeItem(at:sharedBackup.deletingLastPathComponent())}
        XCTAssertNotEqual(sharedProject.deletingLastPathComponent(),sharedBackup.deletingLastPathComponent())
        XCTAssertEqual(sharedProject.lastPathComponent,"Music - named copy.fm1project")
        let music=try ProjectFileEnvelope.read(sharedProject),full=try ProjectFileEnvelope.read(sharedBackup)
        XCTAssertEqual(try music.snapshot.bytes("flash"),Data(repeating:255,count:1<<20))
        for name in ["object1","object10","object11"] {XCTAssertTrue(try music.snapshot.bytes(name).isEmpty)}
        for part in snapshot().parts {XCTAssertEqual(try full.snapshot.bytes(part.name),part.bytes)}
        await store.deleteBackup(backup)
        XCTAssertEqual(try Data(contentsOf:sharedBackup),backupBytes,"Sharing must own bytes independent of later library removal")
        XCTAssertEqual(try Data(contentsOf:project.url),projectBytes)
        XCTAssertEqual(try Data(contentsOf:sharedProject),projectBytes);assertUnloaded()
    }
    func testOpenAndExportRejectBorrowedOrLinkedLibraryItems()async throws {
        let external=try save("External",directory:root.appendingPathComponent("External"))
        await store.open(external);XCTAssertNotNil(store.errorMessage)
        do {_ = try await store.exportFile(external);XCTFail("External item must not masquerade as a saved library item")}catch {}
        let link=library.appendingPathComponent("External.fm1backup")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:external.url)
        let linked=ProjectFileItem(id:external.id,name:external.name,createdAt:external.createdAt,kind:.backup,url:link)
        do {_ = try await store.exportFile(linked);XCTFail("Linked library item must be rejected")}catch {}
        do {_ = try await store.inspectImport(link);XCTFail("Linked import must be rejected")}catch {}
        assertUnloaded()
    }
    func testFailedImportedBackupRemovesNewCopyAndPreservesSourceAndLibrary()async throws {
        let existing=try save("Existing recovery"),external=try save("Incoming",directory:root.appendingPathComponent("External"))
        let existingBytes=try Data(contentsOf:existing.url),externalBytes=try Data(contentsOf:external.url)
        await store.importFile(external.url) // No engine selected: apply must fail after writing the tentative copy.
        XCTAssertNotNil(store.errorMessage);await store.refresh()
        XCTAssertEqual(store.items.map(\.id),[existing.id])
        XCTAssertEqual(try Data(contentsOf:existing.url),existingBytes);XCTAssertEqual(try Data(contentsOf:external.url),externalBytes)
        XCTAssertNil(store.recentlyDeletedBackup);assertUnloaded()
    }
    func testSampleFailureIsThrownOnlyToItsOwningSheet()async throws {
        do {try await store.importSample(slotData:Data(count:81920),slot:0,name:"Sample");XCTFail("No selected native engine must reject sample import")}catch {}
        XCTAssertNil(store.errorMessage,"The sample sheet owns its thrown error; dismissing it must not show a second root alert")
        XCTAssertFalse(store.isBusy);assertUnloaded()
    }
}

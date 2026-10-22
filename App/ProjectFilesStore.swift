import Foundation
import Combine
import CryptoKit

struct ProjectFilesError: LocalizedError {
    let message:String
    var errorDescription:String? {message}
    init(_ message:String){self.message=message}
}

/// A versioned musical workspace, not a dump of process memory. Held notes,
/// playback position and a SONG REC pass in progress are intentionally excluded.
struct SloopWorkSnapshot:Codable,Sendable {
    struct Part:Codable,Sendable {
        let name:String
        let bytes:Data
        let sha256:String
        init(_ name:String,_ bytes:Data){self.name=name;self.bytes=bytes;sha256=SloopWorkSnapshot.digest(bytes)}
    }
    let version:Int
    let packageSHA256:String
    let master:UInt32
    var parts:[Part]
    static func digest(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static var names:Set<String> {Set(["flash","arrangement"]+(0..<12).map{"object\($0)"}+(0..<4).map{"sample\($0)"})}
    func validate()throws {
        guard version == 1,master <= 1023,SloopVersionMigration.supportedSnapshotHashes.contains(packageSHA256),parts.count == Self.names.count,Set(parts.map(\.name)) == Self.names else {throw ProjectFilesError("This workspace format or SLOOP version is not supported.")}
        for part in parts {
            let limit=part.name == "flash" ? 1<<20 : (part.name.hasPrefix("sample") ? 81920 : 65536)
            guard part.bytes.count <= limit,Self.digest(part.bytes) == part.sha256 else {throw ProjectFilesError("A workspace component failed its size or checksum check.")}
        }
        guard try bytes("flash").count == 1<<20,(13...43).contains(try bytes("arrangement").count),!(try bytes("object0")).isEmpty else {throw ProjectFilesError("The workspace is incomplete.")}
        for slot in 0..<4 {guard try bytes("sample\(slot)").count == 81920 else {throw ProjectFilesError("A required sample slot is incomplete.")}}
    }
    func bytes(_ name:String)throws->Data {
        guard let part=parts.first(where:{$0.name == name}) else {throw ProjectFilesError("A required workspace component is missing.")};return part.bytes
    }
    func replacingSample(_ data:Data,slot:Int)throws->Self {
        guard (0..<4).contains(slot),data.count == 81920 else {throw ProjectFilesError("Choose a valid SLOOP user sample slot.")}
        var copy=self;copy.parts.removeAll{$0.name == "sample\(slot)"};copy.parts.append(Part("sample\(slot)",data));return copy
    }
    /// Shared project files contain musical dependencies, never the private raw
    /// workspace, settings, learned MIDI map or personal display theme.
    func projectPayload()->Self {
        let discarded=Set(["flash","object1","object10","object11"])
        return Self(version:version,packageSHA256:packageSHA256,master:716,parts:parts.map {part in
            guard discarded.contains(part.name) else{return part}
            return Part(part.name,part.name == "flash" ? Data(repeating:255,count:1<<20) : Data())
        })
    }
    /// Opening a musical project preserves unrelated settings, MIDI map and
    /// theme. Shared sound banks and USR1–4 are dependencies of this first format.
    func projectOverlay(on current:Self)throws->Self {
        try validate();try current.validate()
        let imported=Set(["object0","arrangement"]+(2...9).map{"object\($0)"}+(0..<4).map{"sample\($0)"})
        return Self(version:1,packageSHA256:current.packageSHA256,master:current.master,parts:current.parts.map { original in imported.contains(original.name) ? parts.first(where:{$0.name == original.name})! : original })
    }
    static func capture(machine:UnsafeMutableRawPointer,master:UInt32=716)throws->Self {
        guard instrument_native_kind(machine) == 2 else {throw ProjectFilesError("Project files currently support SLOOP 2.8.")}
        var parts:[Part]=[]
        var flash=Data(count:1<<20)
        guard flash.withUnsafeMutableBytes({instrument_flash(machine,$0.bindMemory(to:UInt8.self).baseAddress,1<<20)}) == flash.count else {throw ProjectFilesError("Couldn’t capture the complete workspace.")}
        parts.append(Part("flash",flash))
        var arrangement=Data(count:43)
        let count=arrangement.withUnsafeMutableBytes{instrument_sloop_arrangement_read(machine,$0.bindMemory(to:UInt8.self).baseAddress,43)}
        guard count >= 13,count <= 43,arrangement[4] == 0,arrangement[5] == 0 else {throw ProjectFilesError("Stop the song and finish SONG REC before saving or exporting this project.")}
        arrangement.count=Int(count)
        // A reusable project starts stopped, without a queued scene transition.
        for index in [1,4,5,6,7] {arrangement[index]=0}
        parts.append(Part("arrangement",arrangement))
        for id in 0..<12 {
            var data=Data(count:65536)
            let count=data.withUnsafeMutableBytes{instrument_sloop_object_read(machine,UInt32(id),$0.bindMemory(to:UInt8.self).baseAddress,65536)}
            guard count >= 0,count <= 65536 else {throw ProjectFilesError("Couldn’t capture SLOOP object \(id).")}
            data.count=Int(count);parts.append(Part("object\(id)",data))
        }

        for slot in 0..<4 {
            var data=Data(count:81920)
            guard data.withUnsafeMutableBytes({instrument_sloop_sample_read(machine,UInt32(slot),$0.bindMemory(to:UInt8.self).baseAddress,81920)}) == 81920 else {throw ProjectFilesError("Couldn’t capture a required user sample.")}
            parts.append(Part("sample\(slot)",data))
        }
        let result=Self(version:1,packageSHA256:SloopExecutionMode.packageSHA256,master:master,parts:parts);try result.validate();return result
    }
    /// All calls, including destruction by the caller, belong on one serial queue.
    func nativeCreate(package:Data)throws->UnsafeMutableRawPointer {
        try validate()
        guard Self.digest(package) == SloopExecutionMode.packageSHA256 else {throw ProjectFilesError("Install the matching SLOOP 2.8 instrument before opening this file.")}
        var error=[UInt8](repeating:0,count:512)
        guard let candidate=package.withUnsafeBytes({instrument_create($0.bindMemory(to:UInt8.self).baseAddress,package.count,&error,error.count)}) else {throw ProjectFilesError("Couldn’t create the project preview engine.")}
        do {
            guard instrument_native_kind(candidate) == 2 else {throw ProjectFilesError("The required native SLOOP engine is unavailable.")}
            let flash=try bytes("flash")
            guard flash.withUnsafeBytes({instrument_restore(candidate,$0.bindMemory(to:UInt8.self).baseAddress,flash.count)}) else {throw ProjectFilesError("The workspace storage could not be restored.")}
            _=instrument_sloop_transport(candidate,false)
            // Settings, dependencies and saved sections precede the current loop.
            for id in Array(1..<12)+[0] {
                let data=try bytes("object\(id)")
                var buffer=data.isEmpty ? Data([0]) : data
                let rc=buffer.withUnsafeMutableBytes{instrument_sloop_object_write(candidate,UInt32(id),$0.bindMemory(to:UInt8.self).baseAddress,data.count)}
                guard rc == 0 else {throw ProjectFilesError("SLOOP rejected workspace object \(id) (\(rc)).")}
            }
            guard instrument_sloop_commit(candidate) == 0 else {throw ProjectFilesError("The working project could not be saved durably.")}
            let arrangement=try bytes("arrangement")
            guard arrangement.withUnsafeBytes({instrument_sloop_arrangement_write(candidate,$0.bindMemory(to:UInt8.self).baseAddress,arrangement.count)}) == 0 else {throw ProjectFilesError("The song arrangement is invalid.")}
            for slot in 0..<4 {
                let data=try bytes("sample\(slot)")
                guard data.withUnsafeBytes({instrument_sloop_sample_write(candidate,UInt32(slot),$0.bindMemory(to:UInt8.self).baseAddress,data.count)}) == 0 else {throw ProjectFilesError("SLOOP rejected sample slot USR\(slot+1).")}
                var readback=Data(count:81920)
                guard readback.withUnsafeMutableBytes({instrument_sloop_sample_read(candidate,UInt32(slot),$0.bindMemory(to:UInt8.self).baseAddress,81920)}) == 81920,readback == data else {throw ProjectFilesError("Sample verification failed. Your current work was kept.")}
            }
            guard instrument_sloop_commit(candidate) == 0 else {throw ProjectFilesError("The project could not be committed.")}
            instrument_volume(candidate,master)
            return candidate
        } catch {instrument_destroy(candidate);throw error}
    }
}

enum ProjectFileKind:String,Codable,Sendable {case project,backup}
struct ProjectFileItem:Identifiable,Sendable {
    let id:UUID
    let name:String
    let createdAt:Date
    let kind:ProjectFileKind
    let url:URL
}
struct ProjectFileCapabilities {
    let canSaveProject:Bool,canOpenProject:Bool,canBackup:Bool,canImportSamples:Bool,canExportAudio:Bool,canMIDI:Bool
    let explanation:String
}
struct ProjectFileImportPreview:Identifiable {
    let id=UUID()
    let name:String,kind:ProjectFileKind,firmwareName:String,compatibilitySummary:String,dependenciesSummary:String
    let stagedURL:URL
    let canOpen:Bool
}
struct ProjectFileEnvelope:Codable,Sendable {
    let format:String
    let version:Int
    let id:UUID
    let name:String
    let createdAt:Date
    let kind:ProjectFileKind
    var snapshot:SloopWorkSnapshot
    init(name:String,kind:ProjectFileKind,snapshot:SloopWorkSnapshot){format="FM1 SLOOP workspace";version=1;id=UUID();self.name=String(name.prefix(120));createdAt=Date();self.kind=kind;self.snapshot=kind == .project ? snapshot.projectPayload() : snapshot}
    func validate()throws {
        guard format == "FM1 SLOOP workspace",version == 1,!name.isEmpty,name.count <= 120 else {throw ProjectFilesError("This is not a supported FM1 project or backup.")}
        try snapshot.validate()
    }
    func encoded()throws->Data {
        var clean=self
        if kind == .project {clean.snapshot=snapshot.projectPayload()}
        try clean.validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        let data=try encoder.encode(clean)
        guard data.count <= 4*1024*1024 else {throw ProjectFilesError("The workspace is too large for this file format.")}
        return data
    }
    static func read(_ url:URL)throws->Self {
        let values=try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
        guard url.isFileURL,values.isRegularFile == true,values.isSymbolicLink != true else {throw ProjectFilesError("Choose a regular project or backup file, not a link or folder.")}
        let size=values.fileSize ?? 0
        guard (1...4*1024*1024).contains(size) else {throw ProjectFilesError("This project file has an invalid size.")}
        let result=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url));try result.validate()
        let expected=result.kind == .backup ? "fm1backup" : "fm1project"
        guard url.pathExtension.lowercased() == expected else {throw ProjectFilesError("The file type does not match its contents. Projects and workspace backups cannot be interchanged.")}
        return result
    }
}

@MainActor final class ProjectFilesStore:ObservableObject {
    @Published private(set) var items:[ProjectFileItem]=[]
    @Published private(set) var recentlyDeletedBackup:ProjectFileItem?
    @Published private(set) var isBusy=false
    @Published private(set) var progress:Double?
    @Published private(set) var errorMessage:String?
    @Published private(set) var status:String?
    private let instrument:Instrument
    private let io=DispatchQueue(label:"fm1.project-files",qos:.utility)
    let directory:URL
    init(instrument:Instrument,directory:URL?=nil){self.instrument=instrument;self.directory=directory ?? instrument.directory.appendingPathComponent("Projects",isDirectory:true)}
    var capabilities:ProjectFileCapabilities {
        let supported=instrument.supportsProjectFiles
        return ProjectFileCapabilities(canSaveProject:supported,canOpenProject:supported,canBackup:supported,canImportSamples:supported,canExportAudio:supported,canMIDI:false,explanation:supported ? "Saved copies include SLOOP’s loop, sections, song and sounds. Full backups also include instrument settings." : "Saved copies, WAV samples and audio export are available with SLOOP 2.8. Other instruments keep their local autosaves. Close this window to change instrument.")
    }
    private func disk<T>(_ operation:@escaping ()throws->T)async throws->T {try await withCheckedThrowingContinuation {continuation in io.async {do {continuation.resume(returning:try operation())}catch {continuation.resume(throwing:error)}}}}
    private func begin()throws {guard !isBusy else {throw ProjectFilesError("Another file action is still running.")};isBusy=true;errorMessage=nil;status=nil;progress=nil}
    private func finish(){isBusy=false;progress=nil}
    private struct DeletedBackupReceipt:Codable {
        let id:UUID
        let originalFilename:String
        let deletedAt:Date
    }
    nonisolated private static func ownedEnvelope(_ item:ProjectFileItem,in directory:URL)throws->ProjectFileEnvelope {
        try checkedDirectory(directory)
        guard item.url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() == directory.standardizedFileURL.resolvingSymlinksInPath() else {throw ProjectFilesError("Choose a file from this instrument’s saved-copy library.")}
        let envelope=try ProjectFileEnvelope.read(item.url)
        guard envelope.id == item.id,envelope.kind == item.kind else {throw ProjectFilesError("This saved file changed. Refresh the library and try again.")}
        return envelope
    }
    nonisolated private static func checkedDirectory(_ url:URL)throws {
        let values=try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard values.isDirectory == true,values.isSymbolicLink != true else {throw ProjectFilesError("The app’s file folder is unavailable or was replaced by a link.")}
    }
    nonisolated private static func deletedBackups(in directory:URL)throws->[(item:ProjectFileItem,receipt:DeletedBackupReceipt)] {
        try checkedDirectory(directory)
        let trash=directory.appendingPathComponent(".DeletedBackups",isDirectory:true)
        guard FileManager.default.fileExists(atPath:trash.path) else{return []}
        try checkedDirectory(trash)
        return try FileManager.default.contentsOfDirectory(at:trash,includingPropertiesForKeys:nil).compactMap {container in
            guard UUID(uuidString:container.lastPathComponent) != nil else{return nil}
            do {
                try checkedDirectory(container)
                let receiptURL=container.appendingPathComponent("receipt.json")
                let values=try receiptURL.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
                guard values.isRegularFile == true,values.isSymbolicLink != true,(1...4096).contains(values.fileSize ?? 0) else{return nil}
                let receipt=try JSONDecoder().decode(DeletedBackupReceipt.self,from:Data(contentsOf:receiptURL))
                let name=receipt.originalFilename
                guard !name.contains("/"),URL(fileURLWithPath:name).lastPathComponent == name,URL(fileURLWithPath:name).pathExtension.lowercased() == "fm1backup" else{return nil}
                let url=container.appendingPathComponent("backup.fm1backup")
                let envelope=try ProjectFileEnvelope.read(url)
                guard envelope.kind == .backup,envelope.id == receipt.id else{return nil}
                return (ProjectFileItem(id:envelope.id,name:envelope.name,createdAt:envelope.createdAt,kind:envelope.kind,url:url),receipt)
            } catch {return nil} // Keep damaged/partial recovery files on disk for manual recovery.
        }.sorted{$0.receipt.deletedAt > $1.receipt.deletedAt}
    }
    func refresh()async {
        do {let result=try await disk { [directory] in
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try Self.checkedDirectory(directory)
            let items=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter{["fm1project","fm1backup"].contains($0.pathExtension.lowercased())}.compactMap {url -> ProjectFileItem? in
                guard let e=try? ProjectFileEnvelope.read(url) else{return nil}
                return ProjectFileItem(id:e.id,name:e.name,createdAt:e.createdAt,kind:e.kind,url:url)
            }.sorted{$0.createdAt > $1.createdAt}
            return (items,try Self.deletedBackups(in:directory).first?.item)
        };items=result.0;recentlyDeletedBackup=result.1}catch {errorMessage=error.localizedDescription}
    }
    func captureExportContext()async throws->(snapshot:SloopWorkSnapshot,package:Data) {
        try begin();defer{finish()};return try await instrument.captureSloopExportContext()
    }
    func saveCurrent(name:String)async {
        do {try begin();defer{finish()};let context=try await instrument.captureSloopExportContext();let e=ProjectFileEnvelope(name:name.trimmingCharacters(in:.whitespacesAndNewlines),kind:.project,snapshot:context.snapshot);try e.validate();_ = try await write(e);status="Project copy saved.";await refresh()}catch {errorMessage=error.localizedDescription}
    }
    private func write(_ envelope:ProjectFileEnvelope)async throws->URL {
        try await disk { [directory] in
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try Self.checkedDirectory(directory)
            let url=directory.appendingPathComponent(envelope.id.uuidString).appendingPathExtension(envelope.kind == .backup ? "fm1backup" : "fm1project")
            try envelope.encoded().write(to:url,options:.atomic);return url
        }
    }
    private func apply(_ envelope:ProjectFileEnvelope,sampleSlot:Int?=nil,sampleTrack:Int?=nil)async throws {
        try envelope.validate()
        let recovery=directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("fm1backup")
        try await instrument.replaceSloopWork(envelope.snapshot,kind:envelope.kind,recoveryURL:recovery,sampleSlot:sampleSlot,sampleTrack:sampleTrack)
        status=envelope.kind == .backup ? "Workspace restored. A recovery backup was saved first." : "Project opened as a copy. Previous work is in a recovery backup."
        await refresh()
    }
    func open(_ item:ProjectFileItem)async {
        do {try begin();defer{finish()};let e=try await disk{[directory] in try Self.ownedEnvelope(item,in:directory)};try await apply(e)}
        catch {let message=error.localizedDescription;await refresh();errorMessage=message}
    }
    /// Removal changes only the library. The complete original bytes remain in
    /// app-owned recovery storage, and Undo survives a store/app restart.
    func deleteBackup(_ item:ProjectFileItem)async {
        do {
            try begin();defer{finish()}
            try await disk { [directory] in
                guard item.kind == .backup else {throw ProjectFilesError("Only workspace backups can be deleted here.")}
                let envelope=try Self.ownedEnvelope(item,in:directory)
                let trash=directory.appendingPathComponent(".DeletedBackups",isDirectory:true)
                try FileManager.default.createDirectory(at:trash,withIntermediateDirectories:true)
                try Self.checkedDirectory(trash)
                let container=trash.appendingPathComponent(UUID().uuidString,isDirectory:true)
                try FileManager.default.createDirectory(at:container,withIntermediateDirectories:false)
                do {
                    let receipt=DeletedBackupReceipt(id:envelope.id,originalFilename:item.url.lastPathComponent,deletedAt:Date())
                    try JSONEncoder().encode(receipt).write(to:container.appendingPathComponent("receipt.json"),options:.atomic)
                    try FileManager.default.moveItem(at:item.url,to:container.appendingPathComponent("backup.fm1backup"))
                } catch {try? FileManager.default.removeItem(at:container);throw error}
            }
            await refresh();status="Backup removed. You can undo this deletion."
        } catch {errorMessage=error.localizedDescription}
    }
    func restoreDeletedBackup()async {
        do {
            try begin();defer{finish()}
            try await disk { [directory] in
                guard let deleted=try Self.deletedBackups(in:directory).first else {throw ProjectFilesError("There is no deleted backup to restore.")}
                let destination=directory.appendingPathComponent(deleted.receipt.originalFilename)
                let linked=(try? FileManager.default.destinationOfSymbolicLink(atPath:destination.path)) != nil
                guard !FileManager.default.fileExists(atPath:destination.path),!linked else {throw ProjectFilesError("A file already uses this backup’s original location. It was kept, and the deleted backup is still available to undo.")}
                try FileManager.default.moveItem(at:deleted.item.url,to:destination)
                try? FileManager.default.removeItem(at:deleted.item.url.deletingLastPathComponent())
            }
            await refresh();status="Backup restored to the library. Current work was not changed."
        } catch {errorMessage=error.localizedDescription}
    }
    func inspectImport(_ url:URL)async throws->ProjectFileImportPreview {
        try begin();defer{finish()}
        let result:(ProjectFileEnvelope,URL)=try await disk { [directory] in
            let e=try ProjectFileEnvelope.read(url)
            let staged=directory.appendingPathComponent("Staging",isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try Self.checkedDirectory(directory)
            try FileManager.default.createDirectory(at:staged,withIntermediateDirectories:true)
            try Self.checkedDirectory(staged)
            let target=staged.appendingPathComponent(UUID().uuidString).appendingPathExtension(e.kind == .backup ? "fm1backup" : "fm1project")
            try e.encoded().write(to:target,options:.atomic);return(e,target)
        }
        return ProjectFileImportPreview(name:result.0.name,kind:result.0.kind,firmwareName:"SLOOP 2.8",compatibilitySummary:capabilities.canOpenProject ? "Matches the active SLOOP instrument." : "Select SLOOP 2.8 before opening this file.",dependenciesSummary:result.0.kind == .backup ? "Replaces SLOOP’s current work, shared sounds and instrument settings. Excludes other instruments, your saved-copy library and app preferences. Opens stopped, from the beginning." : "Replaces the current loop, sections A–D, song arrangement, sound banks and USR1–4. Keeps your instrument settings, MIDI map, theme and master level. Opens stopped, from the beginning.",stagedURL:result.1,canOpen:capabilities.canOpenProject)
    }
    func importFile(_ url:URL)async {
        do {
            try begin();defer{finish()}
            let e=try await disk{try ProjectFileEnvelope.read(url)}
            let saved=try await write(ProjectFileEnvelope(name:e.name,kind:e.kind,snapshot:e.snapshot))
            do {try await apply(e)}catch {try? await disk {try FileManager.default.removeItem(at:saved)};throw error}
            discardStagedImport(url)
            status="Imported as a new local copy. Previous work is backed up.";await refresh()
        }catch {let message=error.localizedDescription;await refresh();errorMessage=message}
    }
    func discardStagedImport(_ url:URL) {
        let staging=directory.appendingPathComponent("Staging",isDirectory:true).standardizedFileURL
        guard url.deletingLastPathComponent().standardizedFileURL == staging else{return}
        io.async { [directory] in
            guard (try? Self.checkedDirectory(directory)) != nil,(try? Self.checkedDirectory(staging)) != nil,
                  url.deletingLastPathComponent().resolvingSymlinksInPath() == staging.resolvingSymlinksInPath() else{return}
            try? FileManager.default.removeItem(at:url)
        }
    }
    nonisolated private static func stageExport(_ e:ProjectFileEnvelope)throws->URL {
        let bytes=try e.encoded()
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("FM1-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let allowed=CharacterSet.alphanumerics.union(CharacterSet(charactersIn:" -_"))
        let clean=String(e.name.unicodeScalars.map{allowed.contains($0) ? Character(String($0)) : "-"}.prefix(80)).trimmingCharacters(in:.whitespacesAndNewlines)
        let url=folder.appendingPathComponent(clean.isEmpty ? "SLOOP workspace" : clean).appendingPathExtension(e.kind == .backup ? "fm1backup" : "fm1project")
        do {try bytes.write(to:url,options:.atomic);return url}
        catch {try? FileManager.default.removeItem(at:folder);throw error}
    }
    func exportFile(_ item:ProjectFileItem)async throws->URL {
        try begin();defer{finish()}
        return try await disk {[directory] in try Self.stageExport(Self.ownedEnvelope(item,in:directory))}
    }
    func exportCurrentBackup()async throws->URL {
        try begin();defer{finish()};let context=try await instrument.captureSloopExportContext()
        let e=ProjectFileEnvelope(name:"SLOOP workspace backup",kind:.backup,snapshot:context.snapshot)
        _ = try await write(e);await refresh()
        let staged=try await disk {try Self.stageExport(e)}
        status="Complete SLOOP workspace backup prepared. Other instruments and the project library are not included.";return staged
    }
    func importSample(slotData:Data,slot:Int,name:String,targetTrack:Int?=nil)async throws {
        try begin();defer{finish()}
        do {
            let context=try await instrument.captureSloopExportContext()
            let changed=try context.snapshot.replacingSample(slotData,slot:slot)
            try await apply(ProjectFileEnvelope(name:name,kind:.project,snapshot:changed),sampleSlot:slot,sampleTrack:targetTrack)
            if let targetTrack {status="Added to USR\(slot+1) and assigned to Track \(targetTrack+1). Play it on the keyboard. Previous work is in Recovery & backups."}
            else {status="Added to USR\(slot+1). Play with SAMPLE → SET → USR\(slot+1), or GRAIN → SRC. Previous work is in Recovery & backups."}
        } catch {
            await refresh();errorMessage=nil
            throw error // The sample sheet owns this error; do not defer a duplicate root alert.
        }
    }
}

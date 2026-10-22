import Foundation

/// SLOOP 2.8 retains the 2.7 storage format. Only this exact predecessor is
/// eligible; imported packages with a similar filename never identify a save.
enum SloopVersionMigration {
    static let previousPackageSHA256="7c9d269d15d1c1a48e0ebada7ffa2c2aa196c19d51056fd3f760d322322b335f"
    static var supportedSnapshotHashes:Set<String> {[previousPackageSHA256,SloopExecutionMode.packageSHA256]}

    /// Called on the storage queue only when the new version has no autosave.
    /// Returns bytes, leaving both predecessor package and autosave untouched.
    static func previousWorkspace(in directory:URL,preferredID:String?)throws->Data? {
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey])
        var candidates:[URL]=[]
        for file in files where file.pathExtension.lowercased() == "fwsc" {
            guard let size=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize,
                  (960...4*1024*1024).contains(size),
                  SloopWorkSnapshot.digest(try Data(contentsOf:file)) == previousPackageSHA256 else {continue}
            let save=file.deletingPathExtension().appendingPathExtension("flash")
            if FileManager.default.fileExists(atPath:save.path) {candidates.append(save)}
        }
        let preferred=candidates.first {$0.deletingPathExtension().lastPathComponent == preferredID}
        guard let chosen=preferred ?? (candidates.count == 1 ? candidates.first : nil) else {
            if candidates.count > 1 {throw ProjectFilesError("Multiple SLOOP 2.7.1 workspaces were kept. Open a saved project or backup to choose which work to use in SLOOP 2.8.")}
            return nil
        }
        let bytes=try Data(contentsOf:chosen)
        guard bytes.count == 1<<20 else {throw ProjectFilesError("The previous SLOOP workspace has an invalid size. Its original file was kept unchanged.")}
        return bytes
    }
}

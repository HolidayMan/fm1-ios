import SwiftUI
import CryptoKit

struct CatalogFirmware: Codable, Identifiable {
    let id, name, version, author, url, sha256, source: String
    let size: Int
    let beta: Bool
    var nativeEngineName:String? {NativeFirmwareSupport.name(forSHA256:sha256)}
    var filename: String { "\(name)-\(version)".replacingOccurrences(of: "/", with: "-") }
    static let bundled: [Self] = {
        UIResponsivenessProbe.shared.measure("Catalogue.decodeAndSort") {
        guard let url = Bundle.main.url(forResource: "FirmwareCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        let priority=["sloop":0,"official-open":1,"felucca":2,"x0x":3,"melodee":4]
        let ranks=Dictionary(uniqueKeysWithValues:entries.map {entry in
            (entry.id,entry.nativeEngineName == nil ? (entry.id == "stock" ? 5 : 6) : (priority[entry.id] ?? 6))
        })
        return entries.sorted { a,b in
            if ranks[a.id] != ranks[b.id] {return ranks[a.id,default:6] < ranks[b.id,default:6]}
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        }
    }()
    /// Only exact releases backed by an engine linked into this app are offered.
    static let available:[Self] = bundled.filter {$0.nativeEngineName != nil}
    var downloadSize:String {ByteCountFormatter.string(fromByteCount:Int64(size),countStyle:.file)}
    func stageDownload(from temporaryURL:URL)throws->URL {
        let size=try temporaryURL.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size == self.size,size <= 4*1024*1024 else {throw URLError(.dataLengthExceedsMaximum)}
        let data=try Data(contentsOf:temporaryURL)
        try validate(data)
        // The importer uses the file's basename as its display name. Uniqueness
        // belongs to the private parent directory, never the instrument's name.
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("FM1Download-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let staging=folder.appendingPathComponent(filename).appendingPathExtension("fwsc")
        do {try data.write(to:staging,options:.atomic)}
        catch {try? FileManager.default.removeItem(at:folder);throw error}
        return staging
    }
    func validate(_ data: Data) throws {
        guard data.count == size, data.count <= 4 * 1024 * 1024,
              SHA256.hash(data: data).map({String(format:"%02x",$0)}).joined() == sha256 else {
            throw NSError(domain:"FirmwareCatalog",code:1,userInfo:[NSLocalizedDescriptionKey:"The download did not match this release. Please try again."])
        }
    }
}

struct FirmwareLibraryView: View {
    // Live LCD/LED frames must not invalidate the searchable catalogue.
    let instrument: Instrument
    @State private var installed: [Firmware] = []
    @State private var selectedID: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var downloading: String?
    @State private var downloadTask: Task<Void,Never>?
    @State private var error: String?
    @AppStorage("panelFinish") private var finishName=PanelFinish.black.rawValue
    private var finish:PanelFinish {PanelFinish(rawValue:finishName) ?? .black}
    private var theme:FM1SurfaceTheme {FM1SurfaceTheme(finish:finish)}
    private let catalog = CatalogFirmware.available
    private var filtered: [CatalogFirmware] { catalog.filter { query.isEmpty || "\($0.name) \($0.author)".localizedCaseInsensitiveContains(query) } }
    var body: some View {
        UIResponsivenessProbe.shared.measure("FirmwareLibrary.description") {
        NavigationStack {
            List {
                if installed.isEmpty && query.isEmpty {
                    Section {
                        Text("Choose a release below to download before playing. The download size is shown for each release.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if !installed.isEmpty {
                    Section("On this device") {
                        ForEach(installed.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { fw in
                            Button {instrument.load(fw);dismiss()} label: {
                                HStack {Text(fw.name).foregroundStyle(.primary);Spacer();Image(systemName:selectedID == fw.id ? "checkmark.circle.fill" : "play.circle")}
                            }.accessibilityIdentifier("Installed firmware \(fw.id)")
                        }
                    }
                }
                Section {
                    ForEach(filtered) { entry in
                        HStack(spacing:16) {
                            VStack(alignment:.leading,spacing:4) {
                                Text(entry.name).font(.headline)
                                Text("\(entry.version) · \(entry.author)").font(.caption).foregroundStyle(.secondary)
                                Text("\(entry.downloadSize) download").font(.caption).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("Download size \(entry.id)")
                                if entry.id == "official-open" {
                                    Text("Preview · sound differs from the hardware; original factory sounds are not included.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if entry.beta {Text("Beta").font(.caption2).foregroundStyle(.orange)}
                                if let source=URL(string:entry.source) {Link("Project and release",destination:source).font(.caption2)}
                            }
                            Spacer(minLength:0)
                            Button {download(entry)} label: {
                                if downloading == entry.id {ProgressView().frame(width:44,height:44)}
                                else {Image(systemName:"arrow.down.circle").font(.title2).frame(width:44,height:44)}
                            }.buttonStyle(.borderless).accessibilityIdentifier("Download \(entry.name)").accessibilityLabel(downloading == entry.id ? "Downloading \(entry.name)" : "Download \(entry.name), \(entry.downloadSize)")
                        }
                    }
                } header:{Text("Available releases · \(catalog.count)")}
                footer:{Text("Downloads and saved sounds stay on this device. Each release keeps separate saved sounds. Only releases included in this version of the app are offered. FM1 Open is a preview with its own saved sounds and can sound different from the hardware.")}
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .scrollDismissesKeyboard(.immediately)
            .disabled(busy || downloading != nil)
            .searchable(text:$query,placement:.navigationBarDrawer(displayMode:.always),prompt:"Find a firmware")
            .navigationTitle("Firmware library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {Button(downloading == nil ? "Done" : "Cancel") {downloadTask?.cancel();dismiss()}}
            .alert("Download unavailable",isPresented:Binding(get:{error != nil},set:{if !$0 {error=nil}})) {Button("OK"){error=nil}} message:{Text(error ?? "")}
        }
        .tint(theme.accent)
        .onAppear {instrument.refresh()}
        .onReceive(instrument.$firmwares.removeDuplicates()) {installed=$0}
        .onReceive(instrument.$selected.map { $0?.id }.removeDuplicates()) {selectedID=$0}
        .onReceive(instrument.$busy.removeDuplicates()) {busy=$0}
        .onDisappear {downloadTask?.cancel()}
        }
    }
    private func download(_ entry: CatalogFirmware) {
        downloading=entry.id
        downloadTask=Task { @MainActor in
            defer {downloading=nil}
            do {
                guard let url=URL(string:entry.url),url.scheme == "https" else {throw URLError(.badURL)}
                var request=URLRequest(url:url);request.timeoutInterval=45;request.setValue("FM1-iOS/\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1")",forHTTPHeaderField:"User-Agent")
                let (temp,response)=try await URLSession.shared.download(for:request)
                defer {try? FileManager.default.removeItem(at:temp)}
                guard let http=response as? HTTPURLResponse,http.statusCode == 200 else {throw URLError(.badServerResponse)}
                // File reads, digest validation and atomic staging may fault disk
                // pages; none belongs on the thread that animates/searches the list.
                let staging=try await Task.detached(priority:.userInitiated) {
                    try entry.stageDownload(from:temp)
                }.value
                do {try Task.checkCancellation()}
                catch {try? FileManager.default.removeItem(at:staging);throw error}
                // The serial core importer validates compatibility and owns cleanup.
                instrument.importFirmware(staging, removeAfterImport: true)
                dismiss()
            } catch is CancellationError {} catch let e as URLError where e.code == .cancelled {} catch {self.error=error.localizedDescription}
        }
    }
}

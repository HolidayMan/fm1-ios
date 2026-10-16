import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

struct CatalogFirmware: Codable, Identifiable {
    let id, name, version, author, url, sha256, source: String
    let size: Int
    let beta: Bool
    var filename: String { "\(name)-\(version)".replacingOccurrences(of: "/", with: "-") }
    static var bundled: [Self] {
        guard let url = Bundle.main.url(forResource: "FirmwareCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return entries.sorted { a,b in
            let rank: (Self) -> Int = { $0.id == "stock" ? 0 : ($0.id == "felucca" ? 1 : 2) }
            if rank(a) != rank(b) {return rank(a) < rank(b)}
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    func validate(_ data: Data) throws {
        guard data.count == size, data.count <= 4 * 1024 * 1024,
              SHA256.hash(data: data).map({String(format:"%02x",$0)}).joined() == sha256 else {
            throw NSError(domain:"FirmwareCatalog",code:1,userInfo:[NSLocalizedDescriptionKey:"The download did not match this release. Please try again."])
        }
    }
}

struct FirmwareLibraryView: View {
    @ObservedObject var instrument: Instrument
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var query = ""
    @State private var downloading: String?
    @State private var downloadTask: Task<Void,Never>?
    @State private var error: String?
    private let catalog = CatalogFirmware.bundled
    private var filtered: [CatalogFirmware] { catalog.filter { query.isEmpty || "\($0.name) \($0.author)".localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {importing=true} label:{Label("Import .fwsc from Files",systemImage:"folder")}
                }
                if !instrument.firmwares.isEmpty {
                    Section("On this iPhone") {
                        ForEach(instrument.firmwares.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { fw in
                            Button {instrument.load(fw);dismiss()} label: {
                                HStack {Text(fw.name).foregroundStyle(.primary);Spacer();Image(systemName:instrument.selected?.id == fw.id ? "checkmark.circle.fill" : "play.circle")}
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
                                Text(entry.id == "stock" || entry.id == "felucca" ? "Boot and audio checked" : "Not yet tested on iPhone").font(.caption2).foregroundStyle(.secondary)
                                if entry.beta {Text("Beta").font(.caption2).foregroundStyle(.orange)}
                                if let source=URL(string:entry.source) {Link("Source & release",destination:source).font(.caption2)}
                            }
                            Spacer(minLength:0)
                            Button {download(entry)} label: {
                                if downloading == entry.id {ProgressView().frame(width:44,height:44)}
                                else {Image(systemName:"arrow.down.circle").font(.title2).frame(width:44,height:44)}
                            }.buttonStyle(.borderless).accessibilityLabel("Download \(entry.name)")
                        }
                    }
                } header:{Text("Explore · \(catalog.count) firmwares")}
                footer:{Text("Downloads stay on this device. Every version keeps separate saved sounds. Catalogue: 16 October 2026 · FM-1 Firmware Hub and M-VAVE. Compatibility and speed vary by firmware.")}
            }
            .scrollDismissesKeyboard(.immediately)
            .disabled(instrument.busy || downloading != nil)
            .searchable(text:$query,placement:.navigationBarDrawer(displayMode:.always),prompt:"Find a firmware")
            .navigationTitle("Firmwares")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {Button(downloading == nil ? "Done" : "Cancel") {downloadTask?.cancel();dismiss()}}
            .fileImporter(isPresented:$importing,allowedContentTypes:[.data]) { result in
                switch result {
                case .success(let url):instrument.importFirmware(url);dismiss()
                case .failure(let e):error=e.localizedDescription
                }
            }
            .alert("Download unavailable",isPresented:Binding(get:{error != nil},set:{if !$0 {error=nil}})) {Button("OK"){error=nil}} message:{Text(error ?? "")}
        }
        .onAppear {instrument.refresh()}
        .onDisappear {downloadTask?.cancel()}
    }
    private func download(_ entry: CatalogFirmware) {
        downloading=entry.id
        downloadTask=Task { @MainActor in
            defer {downloading=nil}
            do {
                guard let url=URL(string:entry.url),url.scheme == "https" else {throw URLError(.badURL)}
                var request=URLRequest(url:url);request.timeoutInterval=45;request.setValue("FM1-iOS/0.2",forHTTPHeaderField:"User-Agent")
                let (temp,response)=try await URLSession.shared.download(for:request)
                defer {try? FileManager.default.removeItem(at:temp)}
                guard let http=response as? HTTPURLResponse,http.statusCode == 200 else {throw URLError(.badServerResponse)}
                let size=try temp.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                guard size == entry.size,size <= 4*1024*1024 else {throw URLError(.dataLengthExceedsMaximum)}
                let data=try Data(contentsOf:temp);try entry.validate(data);try Task.checkCancellation()
                // Validate through the same core importer as user-owned packages; never overwrite saves.
                let staging=FileManager.default.temporaryDirectory.appendingPathComponent(entry.filename).appendingPathExtension("fwsc")
                try data.write(to:staging,options:.atomic)
                instrument.importFirmware(staging, removeAfterImport: true)
                dismiss()
            } catch is CancellationError {} catch let e as URLError where e.code == .cancelled {} catch {self.error=error.localizedDescription}
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import AVFoundation

private func fm1FileActionCancelled(_ error:Error)->Bool {
    let value=error as NSError
    return error is CancellationError || (value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError)
}

/// A restrained finish tint sits behind native content; glass is for controls.
struct FM1SurfaceTheme {
    let finish:PanelFinish
    var accent:Color {finish.accentColor}
    var contentBackground:Color {Color(uiColor:.secondarySystemGroupedBackground)}
    var background:LinearGradient {
        LinearGradient(colors:[finish.swatch.opacity(0.38),Color(uiColor:.systemGroupedBackground),finish.secondarySwatch.opacity(0.16)],startPoint:.topLeading,endPoint:.bottomTrailing)
    }
}
private struct FM1GlassSurface:ViewModifier {
    let finish:PanelFinish
    let cornerRadius:CGFloat
    let interactive:Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content:Content)->some View {
        let shape=RoundedRectangle(cornerRadius:cornerRadius,style:.continuous)
        if reduceTransparency {
            content.background(FM1SurfaceTheme(finish:finish).contentBackground,in:shape)
        } else if #available(iOS 26.0,*) {
            content.glassEffect(.regular.tint(finish.secondarySwatch.opacity(0.22)).interactive(interactive),in:shape)
        } else {
            content.background(.ultraThinMaterial,in:shape)
                .overlay(shape.strokeBorder(finish.accentColor.opacity(0.14),lineWidth:0.5))
        }
    }
}
extension View {
    func fm1Glass(finish:PanelFinish,cornerRadius:CGFloat=18,interactive:Bool=false)->some View {
        modifier(FM1GlassSurface(finish:finish,cornerRadius:cornerRadius,interactive:interactive))
    }
}
extension UTType {
    static let fm1Project=UTType(exportedAs:"com.local.fm1.project",conformingTo:.json)
    static let fm1Backup=UTType(exportedAs:"com.local.fm1.backup",conformingTo:.json)
}
private struct FM1ExportDocument:FileDocument {
    static var readableContentTypes:[UTType] {[.fm1Project,.fm1Backup,.wav]}
    let data:Data
    init(data:Data){self.data=data}
    init(configuration:ReadConfiguration)throws {data=configuration.file.regularFileContents ?? Data()}
    func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper {FileWrapper(regularFileWithContents:data)}
}
private enum FM1PreparedKind {case project,backup,audio}
private struct FM1PreparedFile:Identifiable {
    let id=UUID()
    let url:URL
    let data:Data
    let kind:FM1PreparedKind
    var type:UTType {switch kind {case .project:return .fm1Project;case .backup:return .fm1Backup;case .audio:return .wav}}
    var contents:String {switch kind {case .project:return "SLOOP loop, sections A–D, song arrangement, sound banks and USR1–4. For SLOOP 2.8 in this app.";case .backup:return "SLOOP work, sounds and instrument settings. Excludes other instruments, saved copies and app preferences.";case .audio:return "Stereo audio mix · 44.1 kHz · 16-bit PCM WAV"}}
}

@MainActor struct ProjectsAndFilesView:View {
    private enum SectionChoice:String,CaseIterable,Identifiable {
        case projects="Saved work",samples="Samples",export="Audio"
        var id:String {rawValue}
    }
    @ObservedObject private var instrument:Instrument
    @StateObject private var store:ProjectFilesStore
    let finish:PanelFinish
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var section:SectionChoice = .projects
    @State private var naming=false
    @State private var copyName=""
    @State private var importing=false
    @State private var importPreview:ProjectFileImportPreview?
    @State private var reviewingImport=false
    @State private var restoreItem:ProjectFileItem?
    @State private var confirmingRestore=false
    @State private var prepared:FM1PreparedFile?
    @State private var preparing=false
    @State private var reviewingExport=false
    @State private var exporting=false
    @State private var sharing=false
    @State private var errorText:String?
    @State private var deliveryStatus:String?
    @State private var choosingSample=false
    @State private var sampleSource:SampleAudioSource?
    @State private var sampleWaveform:[Float]=[]
    @State private var editingSample=false
    @State private var renderMode:PerformanceExport.Mode = .loop
    @State private var renderDuration:Double=15
    @State private var renderTail:Double=2
    @State private var renderProgress:Double?
    @State private var renderTask:Task<Void,Never>?
    init(instrument:Instrument,finish:PanelFinish) {
        self.instrument=instrument;self.finish=finish
        _store=StateObject(wrappedValue:ProjectFilesStore(instrument:instrument))
    }
    private var theme:FM1SurfaceTheme {FM1SurfaceTheme(finish:finish)}
    private var occupied:Bool {instrument.busy || store.isBusy || preparing}
    var body:some View {
        NavigationStack {
            GeometryReader {geometry in
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        Picker("File section",selection:$section) {
                            ForEach(SectionChoice.allCases){Text($0.rawValue).tag($0)}
                        }.pickerStyle(.segmented)
                            .accessibilityIdentifier("Project files section")
                        if occupied {
                            HStack(spacing:12) {
                                if let progress=renderProgress ?? store.progress {ProgressView(value:progress).frame(maxWidth:130)}
                                else {ProgressView()}
                                Text(instrument.busy ? "Loading instrument…" : renderTask != nil ? "Rendering audio…" : preparing ? "Preparing file…" : "Keeping your work safe…").font(.callout)
                                if renderTask != nil {Button("Cancel"){renderTask?.cancel()}.frame(minHeight:44).accessibilityIdentifier("Cancel WAV render")}
                            }.accessibilityElement(children:.contain)
                        }
                        switch section {
                        case .projects: projectsContent(wide:geometry.size.width>=640 && !dynamicType.isAccessibilitySize)
                        case .samples: samplesContent
                        case .export: exportContent
                        }
                        if let status=deliveryStatus ?? store.status {
                            Text(status).font(.callout).foregroundStyle(.secondary)
                                .accessibilityIdentifier("File action status")
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }.padding(.horizontal,16).padding(.vertical,8).frame(maxWidth:960,alignment:.leading).frame(maxWidth:.infinity)
                }
            }
            .background(theme.background)
            .navigationTitle("Projects and files").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}.disabled(occupied)}}
            .tint(theme.accent)
            .task(id:instrument.selected?.id){await store.refresh()}
            .onReceive(store.$errorMessage){if let message=$0 {errorText=message}}
            .interactiveDismissDisabled(occupied)
            .alert("Save a copy",isPresented:$naming) {
                TextField("Project name",text:$copyName)
                Button("Cancel",role:.cancel){}
                Button("Save"){Task{await store.saveCurrent(name:copyName)}}
                    .disabled(copyName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            } message:{Text("Saves the current loop, sections A–D, song arrangement and sounds in this app. Later edits won’t change this copy.")}
            .alert("Couldn’t complete action",isPresented:Binding(get:{errorText != nil && !reviewingExport && !reviewingImport && !editingSample},set:{if !$0 {errorText=nil}})) {
                Button("OK",role:.cancel){}
            } message:{Text(errorText ?? "")}
            .alert(restoreItem?.kind == .backup ? "Restore this SLOOP backup?" : "Open this saved copy?",isPresented:$confirmingRestore) {
                Button(restoreItem?.kind == .backup ? "Back up and restore" : "Back up and open",role:.destructive){if let item=restoreItem {Task{await store.open(item)}}}
                Button("Cancel",role:.cancel){}
            } message:{Text(restoreItem?.kind == .backup
                ? "Replaces SLOOP’s current work, sounds and instrument settings. A recovery backup is saved first. Your saved copies stay unchanged."
                : "Replaces the current loop, sections, song and shared sounds. Instrument settings stay as they are. A recovery backup of your current work is saved first.")}
            .fileImporter(isPresented:$importing,allowedContentTypes:[.fm1Project,.fm1Backup],allowsMultipleSelection:false, onCompletion:inspectImport)
            .sheet(isPresented:$reviewingImport,onDismiss:{
                if let preview=importPreview {store.discardStagedImport(preview.stagedURL)}
                importPreview=nil
            }){importReview}
            .sheet(isPresented:$reviewingExport){exportReview}
            .sheet(isPresented:$editingSample) {
                if let source=sampleSource {
                    FM1SampleTrimView(source:source,waveform:sampleWaveform,finish:finish) {data,slot,name in
                        try await store.importSample(slotData:data,slot:slot,name:name)
                    }
                }
            }
            .fileImporter(isPresented:$choosingSample,allowedContentTypes:[.wav],allowsMultipleSelection:false,onCompletion:loadSample)
        }
    }
    @ViewBuilder private func projectsContent(wide:Bool)->some View {
        if wide {
            HStack(alignment:.top,spacing:28) {
                currentWork.frame(maxWidth:.infinity,alignment:.topLeading)
                projectLibrary.frame(maxWidth:.infinity,alignment:.topLeading)
            }
        } else {VStack(alignment:.leading,spacing:26){currentWork;projectLibrary}}
    }
    private var currentWork:some View {
        VStack(alignment:.leading,spacing:12) {
            Label(instrument.selected?.name ?? "No instrument selected",systemImage:"waveform")
                .font(.headline).fixedSize(horizontal:false,vertical:true)
            if store.capabilities.canSaveProject {
                Text("Keep a named copy of your loop, sections and sounds. Later edits won’t change it.")
                    .font(.callout).foregroundStyle(.secondary)
                action("Save a copy…",symbol:"plus.square.on.square",id:"Save project copy") {
                    copyName="SLOOP \(Date.now.formatted(date:.abbreviated,time:.shortened))";naming=true
                }.disabled(occupied)
                action("Import saved work…",symbol:"square.and.arrow.down",id:"Import project"){importing=true}
                    .disabled(occupied)
                DisclosureGroup("What is saved?") {
                    VStack(alignment:.leading,spacing:8) {
                        Text("A copy includes the current loop (even unsaved edits), sections A–D, song arrangement, sound banks and all four user samples. It opens stopped, from the beginning; held notes and playback position aren’t saved.")
                        Text("These .fm1project and .fm1backup files work with SLOOP 2.8 in this app. They are not hardware FM-1 project files or audio recordings.")
                        Text("Finish SONG REC and stop SONG playback in SLOOP before saving. Ordinary loop playback can continue.")
                    }.font(.caption).foregroundStyle(.secondary).padding(.top,6)
                }.font(.callout)
            } else {
                Text(store.capabilities.explanation).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private var projectLibrary:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Saved copies").font(.headline)
            let copies=store.items.filter{$0.kind == .project}
            if copies.isEmpty {
                Text("No copies yet. Save one to return to this version later.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {ForEach(copies){item in libraryRow(item)}}
            let backups=store.items.filter{$0.kind == .backup}
            if store.capabilities.canBackup || !backups.isEmpty {
                Divider()
                DisclosureGroup("Recovery & backups (\(backups.count))") {
                    VStack(alignment:.leading,spacing:12) {
                        Text("A recovery backup is saved before opening work or replacing a sample. Restore one to undo that replacement, including SLOOP’s sounds and settings.")
                            .font(.caption).foregroundStyle(.secondary)
                        if store.capabilities.canBackup {
                            action("Save full backup…",symbol:"externaldrive",id:"Export backup") {
                                prepare({try await store.exportCurrentBackup()},kind:.backup)
                            }.disabled(occupied)
                            Text("SLOOP only. Other instruments, saved copies and app preferences are not included.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(backups){item in libraryRow(item)}
                    }.padding(.top,8)
                }.font(.callout)
            }
        }
    }
    private func libraryRow(_ item:ProjectFileItem)->some View {
        HStack(spacing:8) {
            Image(systemName:item.kind == .backup ? "externaldrive" : "doc.text").foregroundStyle(theme.accent)
            VStack(alignment:.leading,spacing:3) {
                Text(item.name).font(.body.weight(.medium)).fixedSize(horizontal:false,vertical:true)
                Text(item.createdAt,format:.dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
            Menu {
                Button(item.kind == .backup ? "Restore…" : "Open copy…",systemImage:item.kind == .backup ? "arrow.counterclockwise" : "play") {
                    restoreItem=item;confirmingRestore=true
                }.disabled(!store.capabilities.canOpenProject)
                Button("Export…",systemImage:"square.and.arrow.up"){prepare({try await store.exportFile(item)},kind:item.kind)}
            } label:{Image(systemName:"ellipsis").frame(width:44,height:44)}
                .accessibilityLabel("Actions for \(item.name)").disabled(occupied)
        }.padding(.vertical,4)
    }
    private var samplesContent:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Add a sound to SLOOP").font(.headline)
            if store.capabilities.canImportSamples {
                Text("Choose a WAV, preview and trim it, then choose USR1–USR4. Replaces one shared sound slot; a recovery backup is saved first.")
                    .font(.callout).foregroundStyle(.secondary)
                action("Choose WAV…",symbol:"waveform.badge.plus",id:"Import sample"){choosingSample=true}.disabled(occupied)
                Text("Up to about 7.38 seconds per slot. Converted to mono, 22.05 kHz.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("How to play your sample") {
                    Text("On a synth track, select SAMPLE and set SET to the USR slot you chose. In GRAIN, choose the slot under SRC. This imports one sound, not a multi-sample drum kit.")
                        .font(.callout).foregroundStyle(.secondary).padding(.top,6)
                }.font(.callout)
            } else {
                Text("WAV sample import is available with SLOOP 2.8. Close this window and choose SLOOP from the instrument menu.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.frame(maxWidth:640,alignment:.leading)
    }
    private func loadSample(_ result:Result<[URL],Error>) {
        switch result {
        case .failure(let error):if !fm1FileActionCancelled(error) {errorText=error.localizedDescription}
        case .success(let urls):
            guard let url=urls.first else{return}
            preparing=true
            Task {
                let access=url.startAccessingSecurityScopedResource()
                defer {if access {url.stopAccessingSecurityScopedResource()};preparing=false}
                do {
                    let loaded=try await Task.detached(priority:.userInitiated){
                        let source=try SampleAudioImporter.load(url)
                        return (source,source.waveform)
                    }.value
                    sampleSource=loaded.0;sampleWaveform=loaded.1;editingSample=true
                } catch {errorText=error.localizedDescription}
            }
        }
    }
    private var exportContent:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Export audio as WAV").font(.headline)
            if store.capabilities.canExportAudio {
                Picker("Export source",selection:$renderMode) {
                    ForEach(PerformanceExport.Mode.allCases){Text($0.rawValue).tag($0)}
                }.pickerStyle(.segmented).disabled(occupied).accessibilityIdentifier("Audio export source")
                Text(renderMode == .song ? "Exports the complete A–D song arrangement once, from start to finish, even if repeat is enabled in SLOOP." : "Repeats the current loop for the chosen duration. This does not record your live playing.")
                    .font(.callout).foregroundStyle(.secondary)
                if dynamicType.isAccessibilitySize {
                    VStack(alignment:.leading,spacing:8){if renderMode == .loop {audioDurationControl};audioTailControl}
                } else {
                    HStack(alignment:.top,spacing:24){if renderMode == .loop {audioDurationControl};audioTailControl}
                }
                Text(renderMode == .song ? "Whole song + \(Int(renderTail)) seconds of effect tail · stereo WAV" : "\(Int(renderDuration+renderTail)) seconds total · stereo WAV")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                action("Create WAV…",symbol:"waveform",id:"Export WAV"){renderAudio()}.disabled(occupied)
                DisclosureGroup("About audio export") {
                    VStack(alignment:.leading,spacing:8) {
                        Text("Loop uses the chosen duration. Whole song follows every entry in SLOOP’s arrangement and stops at the end; all referenced sections must be saved. Exports are limited to 30 minutes. Effect tail adds decay after playback stops. Random sounds may differ on each export.")
                        Text("44.1 kHz, 16-bit stereo mix. Your instrument can keep playing while the file is made. Finish SONG REC and stop SONG playback first.")
                        Text("Live recording, MIDI files and separate track exports are not available. To share editable work, use Export in a saved copy’s menu.")
                    }.font(.caption).foregroundStyle(.secondary).padding(.top,6)
                }.font(.callout)
            } else {
                Text("WAV audio export is available with SLOOP 2.8. Close this window and choose SLOOP from the instrument menu.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.frame(maxWidth:640,alignment:.leading)
    }
    private var audioDurationControl:some View {
        VStack(alignment:.leading,spacing:0) {
            Text("Music duration").font(.caption).foregroundStyle(.secondary)
            Picker("Music duration",selection:$renderDuration) {
                ForEach([5.0,15,30,60],id:\.self){Text("\(Int($0)) seconds").tag($0)}
            }.labelsHidden().frame(minHeight:44).disabled(occupied).accessibilityIdentifier("Audio music duration")
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var audioTailControl:some View {
        VStack(alignment:.leading,spacing:0) {
            Text("Effect tail").font(.caption).foregroundStyle(.secondary)
            Picker("Effect tail",selection:$renderTail) {
                Text("None").tag(0.0);Text("2 seconds").tag(2.0);Text("5 seconds").tag(5.0)
            }.labelsHidden().frame(minHeight:44).disabled(occupied).accessibilityIdentifier("Audio effect tail")
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func action(_ title:LocalizedStringKey,symbol:String,id:String,perform:@escaping ()->Void)->some View {
        Button(action:perform) {
            Label(title,systemImage:symbol).font(.body.weight(.medium))
                .frame(minHeight:44).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,14)
                .fm1Glass(finish:finish,cornerRadius:14,interactive:true)
        }.buttonStyle(.plain).foregroundStyle(theme.accent).accessibilityIdentifier(id)
    }
    private func inspectImport(_ result:Result<[URL],Error>) {
        switch result {
        case .failure(let error):if !fm1FileActionCancelled(error) {errorText=error.localizedDescription}
        case .success(let urls):
            guard let url=urls.first else{return}
            preparing=true
            Task {
                let access=url.startAccessingSecurityScopedResource()
                defer {if access {url.stopAccessingSecurityScopedResource()};preparing=false}
                do {importPreview=try await store.inspectImport(url);reviewingImport=true}
                catch {errorText=error.localizedDescription}
            }
        }
    }
    private var importReview:some View {
        NavigationStack {
            if let preview=importPreview {
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        Label(preview.name,systemImage:preview.kind == .backup ? "externaldrive" : "doc.text").font(.title2.weight(.semibold))
                        detail("Source",preview.firmwareName)
                        detail("Compatibility",preview.compatibilitySummary)
                        detail("What changes",preview.dependenciesSummary)
                        Text(preview.kind == .backup ? "Restoring replaces this engine’s workspace. An automatic backup is created first. Named copies in your library stay intact." : "Adds a saved copy and opens it. Your current work is saved in Recovery & backups first.")
                            .font(.callout).foregroundStyle(.secondary)
                        action(preview.kind == .backup ? "Back up and restore" : "Open as a copy",symbol:preview.kind == .backup ? "arrow.counterclockwise" : "doc.on.doc",id:"Confirm project import") {
                            let url=preview.stagedURL
                            importPreview=nil
                            reviewingImport=false
                            Task{await store.importFile(url);store.discardStagedImport(url)}
                        }.disabled(!preview.canOpen || occupied)
                    }.padding(20)
                }.background(theme.background)
                    .navigationTitle(preview.kind == .backup ? "Review backup" : "Review project").navigationBarTitleDisplayMode(.inline)
                    .toolbar {Button("Cancel"){reviewingImport=false}}
            }
        }.tint(theme.accent)
    }
    private func prepare(_ operation:@escaping ()async throws->URL,kind:ProjectFileKind) {
        preparing=true;deliveryStatus=nil
        Task {
            defer {preparing=false}
            do {
                let url=try await operation()
                let data=try await Task.detached(priority:.userInitiated){try Data(contentsOf:url)}.value
                prepared=FM1PreparedFile(url:url,data:data,kind:kind == .backup ? .backup : .project);reviewingExport=true
            } catch {errorText=error.localizedDescription}
        }
    }
    private func renderAudio() {
        preparing=true;deliveryStatus=nil;renderProgress=0
        let duration=renderDuration,tail=renderTail,mode=renderMode
        renderTask=Task {
            defer {preparing=false;renderProgress=nil;renderTask=nil}
            do {
                let context=try await store.captureExportContext()
                let url=try await PerformanceExport.render(snapshot:context.snapshot,package:context.package,duration:duration,tail:tail,mode:mode){value in
                    Task{@MainActor in renderProgress=value}
                }
                try Task.checkCancellation()
                let data=try await Task.detached(priority:.userInitiated){try Data(contentsOf:url)}.value
                prepared=FM1PreparedFile(url:url,data:data,kind:.audio);reviewingExport=true
            } catch is CancellationError {deliveryStatus="Audio rendering cancelled. You can start another take."}
            catch {errorText=error.localizedDescription}
        }
    }
    private var exportReview:some View {
        NavigationStack {
            if let file=prepared {
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        Label(file.url.lastPathComponent,systemImage:file.kind == .audio ? "waveform" : file.kind == .backup ? "externaldrive" : "doc.text").font(.title3.weight(.semibold)).textSelection(.enabled)
                        detail("Contents",file.contents)
                        detail("Size",ByteCountFormatter.string(fromByteCount:Int64(file.data.count),countStyle:.file))
                        Text("Choose where to save or share this file. Cancelling the destination picker returns here.")
                            .font(.callout).foregroundStyle(.secondary)
                        action("Save to Files",symbol:"folder",id:"Save prepared file"){exporting=true}
                        action("Share…",symbol:"square.and.arrow.up",id:"Share prepared file"){sharing=true}
                        if let deliveryStatus {Text(deliveryStatus).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("File delivery status")}
                    }.padding(20)
                }.background(theme.background)
                    .navigationTitle("Review export").navigationBarTitleDisplayMode(.inline)
                    .toolbar {Button("Done"){reviewingExport=false}}
                    .fileExporter(isPresented:$exporting,document:FM1ExportDocument(data:file.data),contentType:file.type,defaultFilename:file.url.deletingPathExtension().lastPathComponent) {result in
                        switch result {
                        case .success:deliveryStatus="Saved to the destination you selected."
                        case .failure(let error):if !fm1FileActionCancelled(error) {errorText=error.localizedDescription}
                        }
                    }
                    .sheet(isPresented:$sharing){FM1FileShare(url:file.url){completed,error in
                        sharing=false
                        if let error {errorText=error.localizedDescription}
                        else if completed {deliveryStatus="Handed off to the selected activity. Delivery is managed by that app."}
                    }}
                    .alert("Couldn’t export file",isPresented:Binding(get:{errorText != nil},set:{if !$0 {errorText=nil}})) {Button("OK",role:.cancel){}} message:{Text(errorText ?? "")}
            }
        }.tint(theme.accent)
    }
    private func detail(_ label:LocalizedStringKey,_ value:String)->some View {
        VStack(alignment:.leading,spacing:4){Text(label).font(.caption).foregroundStyle(.secondary);Text(value).font(.body)}
    }
}
private struct FM1FileShare:UIViewControllerRepresentable {
    let url:URL
    let completion:(Bool,Error?)->Void
    func makeUIViewController(context:Context)->UIActivityViewController {
        let controller=UIActivityViewController(activityItems:[url],applicationActivities:nil)
        controller.completionWithItemsHandler={_,completed,_,error in completion(completed,error)}
        return controller
    }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context){}
}

@MainActor private final class FM1SampleAudition:NSObject,ObservableObject,AVAudioPlayerDelegate {
    @Published private(set) var playing=false
    private var player:AVAudioPlayer?
    func play(_ data:Data)throws {
        stop()
        let audio=try AVAudioPlayer(data:data)
        audio.delegate=self;audio.prepareToPlay()
        guard audio.play() else {throw NSError(domain:"FM1Sample",code:1,userInfo:[NSLocalizedDescriptionKey:"The selected region couldn’t be previewed."])}
        player=audio;playing=true
    }
    func stop(){player?.stop();player=nil;playing=false}
    nonisolated func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool){Task{@MainActor in self.stop()}}
}
@MainActor private struct FM1SampleTrimView:View {
    let source:SampleAudioSource
    let waveform:[Float]
    let finish:PanelFinish
    let apply:(Data,Int,String)async throws->Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var audition=FM1SampleAudition()
    @State private var start:Double=0
    @State private var end:Double=0
    @State private var slot=0
    @State private var normalize=false
    @State private var busy=false
    @State private var confirming=false
    @State private var errorText:String?
    private var theme:FM1SurfaceTheme {FM1SurfaceTheme(finish:finish)}
    private var duration:Double {max(1.0/22050,source.duration)}
    private var encodedBytes:Int {SampleAudioImporter.encodedByteCount(duration:max(0,end-start))}
    private var fits:Bool {end>start && encodedBytes<=81920}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text(source.name).font(.title3.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
                    FM1SampleWaveform(values:waveform,start:start/duration,end:end/duration)
                        .foregroundStyle(theme.accent).frame(height:110)
                        .accessibilityLabel("Sample waveform. Selected region \(start.formatted(.number.precision(.fractionLength(2)))) to \(end.formatted(.number.precision(.fractionLength(2)))) seconds.")
                    Button {preview()} label:{
                        Label(audition.playing ? "Stop preview" : "Audition selected region",systemImage:audition.playing ? "stop.fill" : "play.fill")
                            .frame(minHeight:44).frame(maxWidth:.infinity).padding(.horizontal,14)
                            .fm1Glass(finish:finish,cornerRadius:14,interactive:true)
                    }.buttonStyle(.plain).disabled(busy || end<=start).accessibilityIdentifier("Audition sample")
                    VStack(alignment:.leading,spacing:4) {
                        HStack {
                            Text("Start").font(.callout)
                            Spacer()
                            TextField("Start time",value:Binding(get:{start},set:{setStart($0)}),format:.number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width:100).frame(minHeight:44)
                            Text("s").foregroundStyle(.secondary)
                        }
                        Slider(value:Binding(get:{start},set:{setStart($0)}),in:0...duration).frame(minHeight:44).accessibilityLabel("Sample start")
                        HStack {
                            Text("End").font(.callout)
                            Spacer()
                            TextField("End time",value:Binding(get:{end},set:{setEnd($0)}),format:.number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width:100).frame(minHeight:44)
                            Text("s").foregroundStyle(.secondary)
                        }
                        Slider(value:Binding(get:{end},set:{setEnd($0)}),in:0...duration).frame(minHeight:44).accessibilityLabel("Sample end")
                    }
                    Text("\(Double(encodedBytes)/1024,specifier:"%.1f") KiB / 80 KiB after encoding")
                        .font(.callout.monospacedDigit()).foregroundStyle(fits ? Color.secondary : Color.orange)
                        .accessibilityIdentifier("Encoded sample capacity")
                    if !fits {Text("Trim a shorter region to fit the destination slot.").font(.callout).foregroundStyle(.orange)}
                    Toggle("Normalize selected region",isOn:$normalize).frame(minHeight:44)
                    Text("Converted to 22.05 kHz, mono, FSMP. Normalization applies when adding the sample. The original WAV file is not changed.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Destination",selection:$slot) {ForEach(0..<4){Text("USR\($0+1)").tag($0)}}
                        .pickerStyle(.segmented).frame(minHeight:44).accessibilityIdentifier("Sample destination")
                    Text("Replaces this shared slot in the current SLOOP workspace. Tracks and sections using it will play the new sound. Named saved copies keep their original samples.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("To play it: SAMPLE → SET → USR slot, or GRAIN → SRC → USR slot.").font(.caption).foregroundStyle(.secondary)
                    Button {audition.stop();confirming=true} label:{
                        if busy {ProgressView().frame(minHeight:44).frame(maxWidth:.infinity)}
                        else {Label("Add to USR\(slot+1)…",systemImage:"square.and.arrow.down").frame(minHeight:44).frame(maxWidth:.infinity)}
                    }.buttonStyle(.borderedProminent).disabled(!fits || busy).accessibilityIdentifier("Apply sample")
                }.padding(20).frame(maxWidth:720).frame(maxWidth:.infinity)
            }.background(theme.background).tint(theme.accent)
                .navigationTitle("Trim sample").navigationBarTitleDisplayMode(.inline)
                .toolbar {Button("Cancel"){audition.stop();dismiss()}.disabled(busy)}
                .interactiveDismissDisabled(busy)
                .task {end=duration}
                .onDisappear {audition.stop()}
                .onChange(of:scenePhase){_,phase in if phase != .active {audition.stop()}}
                .confirmationDialog("Replace the sound in USR\(slot+1)?",isPresented:$confirming,titleVisibility:.visible) {
                    Button("Back up and replace",role:.destructive){commit()}
                    Button("Cancel",role:.cancel){}
                } message:{Text("Tracks and sections using this slot will play the new sound. A recovery backup is saved first; named saved copies stay unchanged.")}
                .alert("Sample action failed",isPresented:Binding(get:{errorText != nil},set:{if !$0 {errorText=nil}})) {Button("OK",role:.cancel){}} message:{Text(errorText ?? "")}
        }
    }
    private func setStart(_ value:Double){audition.stop();start=max(0,min(value,end-1.0/22050))}
    private func setEnd(_ value:Double){audition.stop();end=min(duration,max(value,start+1.0/22050))}
    private func preview() {
        if audition.playing {audition.stop();return}
        let begin=start,finish=end,source=source
        busy=true
        Task {
            defer {busy=false}
            do {
                let data=try await Task.detached(priority:.userInitiated){try SampleAudioImporter.previewWAV(source:source,start:begin,end:finish)}.value
                try audition.play(data)
            } catch {errorText=error.localizedDescription}
        }
    }
    private func commit() {
        let begin=start,finish=end,source=source,normalize=normalize,destination=slot
        busy=true
        Task {
            defer {busy=false}
            do {
                let data=try await Task.detached(priority:.userInitiated){try SampleAudioImporter.encode(source:source,start:begin,end:finish,normalize:normalize)}.value
                try await apply(data,destination,source.name)
                dismiss()
            } catch {errorText=error.localizedDescription}
        }
    }
}
private struct FM1SampleWaveform:View {
    let values:[Float]
    let start:Double,end:Double
    var body:some View {
        GeometryReader {geometry in
            ZStack(alignment:.leading) {
                Canvas {context,size in
                    guard !values.isEmpty else{return}
                    var bars=Path()
                    for (index,value) in values.enumerated() {
                        let x=CGFloat(index)*size.width/CGFloat(values.count)
                        let amplitude=CGFloat(min(1,max(0,abs(value))))*size.height/2
                        bars.move(to:CGPoint(x:x,y:size.height/2-amplitude))
                        bars.addLine(to:CGPoint(x:x,y:size.height/2+amplitude))
                    }
                    context.stroke(bars,with:.foreground,lineWidth:2)
                }
                Color.primary.opacity(0.07).frame(width:geometry.size.width*start)
                Color.primary.opacity(0.07).frame(width:geometry.size.width*(1-end)).frame(maxWidth:.infinity,alignment:.trailing)
                Rectangle().frame(width:2).offset(x:geometry.size.width*start)
                Rectangle().frame(width:2).offset(x:geometry.size.width*end)
            }
        }.accessibilityElement(children:.ignore)
    }
}

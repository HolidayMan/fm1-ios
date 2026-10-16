import SwiftUI
import UniformTypeIdentifiers

@main struct FM1App: App {
    @StateObject private var instrument=Instrument()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            InstrumentView(instrument:instrument)
                .preferredColorScheme(.dark)
                .onChange(of:scenePhase) { phase in if phase != .active {instrument.pause()} }
        }
    }
}
struct InstrumentView: View {
    @ObservedObject var instrument:Instrument
    @State private var library=false
    @State private var importing=false
    @State private var display=false
    @State private var about=false
    var body:some View {
        GeometryReader { geo in
            VStack(spacing:0) {
                HStack(spacing:14) {
                    HStack(spacing:7) {
                        Circle().fill(instrument.running ? Color.green : Color.gray).frame(width:5,height:5)
                        Text("FM–1").font(.system(size:15,weight:.semibold,design:.rounded)).tracking(2)
                    }
                    Button {library=true} label:{HStack(spacing:7){Text(instrument.selected?.name ?? "Choose firmware").lineLimit(1);Image(systemName:"chevron.down").font(.system(size:10,weight:.bold))}.font(.system(size:12,weight:.medium)).foregroundStyle(.white.opacity(0.75))}
                        .accessibilityIdentifier("Firmware library")
                    Spacer(minLength:5)
                    if instrument.busy {ProgressView().controlSize(.small)}
                    Button {instrument.running ? instrument.pause() : instrument.resume()} label:{Image(systemName:instrument.running ? "pause.fill" : "play.fill").frame(width:28,height:28)}
                        .disabled(instrument.selected == nil || instrument.busy).accessibilityLabel(instrument.running ? "Pause instrument" : "Resume instrument")
                    Button {instrument.toggleMute()} label:{Image(systemName:instrument.muted ? "speaker.slash" : "speaker.wave.2").frame(width:28,height:28)}.accessibilityLabel("Mute audio")
                    Button {about=true} label:{Image(systemName:"info.circle").frame(width:28,height:28)}.accessibilityLabel("About")
                }.foregroundStyle(.white.opacity(0.85)).padding(.horizontal,20).frame(height:42)
                PanelView(instrument:instrument,showScreen:{display=true})
                    .padding(.horizontal,12)
                HStack {
                    Text(instrument.status)
                    Spacer()
                    Text("Drag knobs · Play chords · Tap display to enlarge")
                }.font(.system(size:9,weight:.medium)).foregroundStyle(.white.opacity(0.35)).padding(.horizontal,24).frame(height:22)
            }
            .frame(width:geo.size.width,height:geo.size.height)
            .background(RadialGradient(colors:[Color(white:0.115),Color(white:0.035)],center:.center,startRadius:0,endRadius:700))
        }.statusBarHidden()
        .sheet(isPresented:$library) {firmwareLibrary}
        .sheet(isPresented:$display) {
            VStack(spacing:18) {
                HStack {Text("Display").font(.headline);Spacer();Button("Done"){display=false}}
                if let image=instrument.screen {Image(decorative:image,scale:1).resizable().interpolation(.none).aspectRatio(contentMode:.fit)}
                else {ContentUnavailableView("No firmware running",systemImage:"display",description:Text("Import an FM-1 firmware to see its display."))}
            }.padding(24).presentationDetents([.large])
        }
        .sheet(isPresented:$about) {
            NavigationStack {
                List {
                    Section("FM–1 · Native prototype") {
                        Text("The FM-1 front panel, a real emulated CPU, and your own firmware packages. Pinch-free playing in landscape on iPhone and iPad.")
                        Text("Core: fm1-emu by Joakim Eriksson · MIT. This independent app is not affiliated with M-VAVE.")
                    }
                    Section("Current build") {
                        Text("Import .fwsc from Files. Firmware saves are kept separately for every imported version. Audio pauses when the app leaves the foreground or the output route changes.")
                        Text("Compatibility and real-time performance vary by firmware. No firmware is included. No microphone, account or network connection is needed.")
                    }
                    Section("Third-party license") {Text((try? String(contentsOf:Bundle.main.url(forResource:"LICENSE-fm1-emu",withExtension:nil)!)) ?? "MIT — Joakim Eriksson, 2026").font(.caption)}
                }.navigationTitle("About").toolbar {Button("Done"){about=false}}
            }
        }
        .alert("Couldn’t load firmware",isPresented:Binding(get:{instrument.message != nil},set:{if !$0{instrument.message=nil}})) {Button("OK"){instrument.message=nil}} message:{Text(instrument.message ?? "")}
    }
    private var firmwareLibrary:some View {
        NavigationStack {
            List {
                Section {
                    Button {importing=true} label:{Label("Import .fwsc from Files",systemImage:"square.and.arrow.down")}.disabled(instrument.busy)
                } footer:{Text("Import an original FM-1 update package. Each version keeps its own saved sounds. Files remain on this device.")}
                Section("On this device") {
                    if instrument.firmwares.isEmpty {Text("Your firmware library is empty.").foregroundStyle(.secondary)}
                    ForEach(instrument.firmwares) {fw in
                        Button {instrument.load(fw);library=false} label:{HStack {VStack(alignment:.leading,spacing:4){Text(fw.name).foregroundStyle(.primary);Text("FM-1 firmware package").font(.caption).foregroundStyle(.secondary)};Spacer();if instrument.selected?.id==fw.id{Image(systemName:"checkmark.circle.fill").foregroundStyle(.green)}else{Image(systemName:"play.circle").foregroundStyle(.secondary)}}}.disabled(instrument.busy)
                    }
                }
            }.navigationTitle("Firmwares").toolbar {Button("Done"){library=false}}
            .fileImporter(isPresented:$importing,allowedContentTypes:[.data],allowsMultipleSelection:false) {result in
                switch result {
                case .success(let urls):if let url=urls.first {instrument.importFirmware(url);library=false}
                case .failure(let error):instrument.message=error.localizedDescription
                }
            }
        }
    }
}

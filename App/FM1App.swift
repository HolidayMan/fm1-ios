import SwiftUI

@main struct FM1App:App {
    @StateObject private var instrument:Instrument
    init() {
        if let relative=ProcessInfo.processInfo.environment[AppLaunchFixture.environmentKey] {
            let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            let fixture=AppLaunchFixture.resolve(relative,documents:documents)
            let model=Instrument(directory:fixture ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),preferences:UserDefaults(suiteName:"LifecycleUI.\(UUID().uuidString)")!)
            if fixture == nil {model.message="The isolated lifecycle fixture is unavailable."}
            _instrument=StateObject(wrappedValue:model)
        } else {_instrument=StateObject(wrappedValue:Instrument())}
    }
    @Environment(\.scenePhase) private var scenePhase
    private var automaticStartupAllowed:Bool {
        !ProcessInfo.processInfo.arguments.contains("--panel-touch-diagnostics") &&
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil && NSClassFromString("XCTestCase") == nil
    }
    var body:some Scene {
        WindowGroup {
            InstrumentView(instrument:instrument)
                .preferredColorScheme(.dark)
                .onAppear {instrument.sceneChanged(active:scenePhase == .active,autoStart:automaticStartupAllowed)}
                .onChange(of:scenePhase) {phase in instrument.sceneChanged(active:phase == .active,autoStart:automaticStartupAllowed)}
        }
    }
}
struct InstrumentView:View {
    @ObservedObject var instrument:Instrument
    @State private var library=false
    @State private var display=false
    @State private var about=false
    @State private var choosingFinish=false
    @AppStorage("panelFinish") private var finishName=PanelFinish.black.rawValue
    private var finish:PanelFinish {PanelFinish(rawValue:finishName) ?? .black}
    var body:some View {
        GeometryReader {geo in
            VStack(spacing:3) {
                HStack(spacing:10) {
                    Button {library=true;ControlHaptics.shared.button()} label:{
                        HStack(spacing:7) {
                            Circle().fill(instrument.running ? Color.green : Color.gray).frame(width:5,height:5)
                            Text(instrument.selected?.name ?? "Choose firmware").lineLimit(1)
                            Image(systemName:"chevron.down").font(.system(size:9,weight:.bold))
                        }.font(.system(size:12,weight:.semibold))
                    }.accessibilityIdentifier("Firmware library")
                    Spacer(minLength:4)
                    if instrument.busy {ProgressView().controlSize(.mini)}
                    Text(instrument.status).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth:160,alignment:.trailing)
                    Button {instrument.playbackWanted ? instrument.pause() : instrument.resume();ControlHaptics.shared.button()} label:{Image(systemName:instrument.playbackWanted ? "pause.fill" : "play.fill").frame(width:31,height:28)}
                        .disabled(instrument.selected == nil || (instrument.busy && !instrument.playbackWanted)).accessibilityLabel(instrument.playbackWanted ? "Pause instrument" : "Resume instrument")
                    Button {instrument.toggleMute();ControlHaptics.shared.button()} label:{Image(systemName:instrument.muted ? "speaker.slash" : "speaker.wave.2").frame(width:31,height:28)}.accessibilityLabel("Mute audio")
                    Button {choosingFinish=true;ControlHaptics.shared.button()} label:{
                        HStack(spacing:0) {Circle().fill(finish.swatch).frame(width:16,height:16);Circle().fill(finish.secondarySwatch).frame(width:16,height:16).padding(.leading,-7)}.frame(width:31,height:28)
                    }.accessibilityLabel("Panel color").accessibilityValue(finish.rawValue)
                    Button {about=true;ControlHaptics.shared.button()} label:{Image(systemName:"info.circle").frame(width:31,height:28)}.accessibilityLabel("About")
                }.foregroundStyle(.white.opacity(0.9)).padding(.horizontal,9).frame(height:29)
                PanelView(instrument:instrument,finish:finish,showScreen:{display=true})
            }.padding(.horizontal,3)
                .frame(width:geo.size.width,height:geo.size.height)
                .background(Color(white:0.055))
        }.ignoresSafeArea(edges:.bottom).statusBarHidden().persistentSystemOverlays(.hidden).defersSystemGestures(on:.bottom)
        .sheet(isPresented:$library) {FirmwareLibraryView(instrument:instrument)}
        .sheet(isPresented:$choosingFinish) {
            NavigationStack {
                VStack {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                        ForEach(PanelFinish.allCases) {option in
                            Button {finishName=option.rawValue;choosingFinish=false;ControlHaptics.shared.button()} label:{
                                HStack(spacing:12) {
                                    HStack(spacing:0) {Circle().fill(option.swatch).frame(width:28,height:28);Circle().fill(option.secondarySwatch).frame(width:28,height:28).padding(.leading,-10)}
                                    Text(option.rawValue).font(.system(size:14,weight:.medium)).foregroundStyle(.primary)
                                    Spacer(minLength:0)
                                    Image(systemName:option==finish ? "checkmark.circle.fill" : "circle").foregroundStyle(option==finish ? Color.mint : Color.secondary)
                                }.padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:12))
                            }.buttonStyle(.plain).accessibilityIdentifier("Finish \(option.rawValue)")
                        }
                    }.padding(16)
                    Spacer(minLength:0)
                }.navigationTitle("Panel color").navigationBarTitleDisplayMode(.inline).toolbar {Button("Done"){choosingFinish=false}}
            }
        }
        .sheet(isPresented:$display) {
            VStack(spacing:18) {
                HStack {Text("Display").font(.headline);Spacer();Button("Done"){display=false}}
                if let image=instrument.screen {Image(decorative:image,scale:1).resizable().interpolation(.none).aspectRatio(contentMode:.fit)}
                else {ContentUnavailableView("No firmware running",systemImage:"display",description:Text("Choose an FM-1 firmware to see its display."))}
            }.padding(24).presentationDetents([.large])
        }
        .sheet(isPresented:$about) {
            NavigationStack {
                List {
                    Section("FM–1 · Native prototype") {
                        Text("A touch instrument inspired by the FM-1, with a real emulated CPU and original firmware controls. Play chords, slide between keys and drag knobs vertically. Tap the display to enlarge it.")
                        Text("Core: fm1-emu by Joakim Eriksson · MIT. This independent app is not affiliated with M-VAVE. Panel colors follow the six finishes shown by M-VAVE; screen colors are approximations.")
                    }
                    Section("Current build") {
                        Text("Choose a firmware from the catalogue or import .fwsc from Files. Downloads require a network connection. Firmware and separate saved sounds stay on this device. Audio pauses when the app leaves the foreground or the output route changes.")
                        Text("Compatibility and real-time performance vary by firmware. The catalogue identifies available releases; it does not certify every version. No microphone or account is needed.")
                    }
                    Section {
                        LabeledContent("Audio engine",value:instrument.audioDiagnostics.backend?.displayName ?? "Not loaded")
                        LabeledContent("Render time / audio time",value:String(format:"%.0f%%",instrument.audioDiagnostics.renderRatioMean*100))
                        LabeledContent("95th percentile",value:String(format:"%.0f%%",instrument.audioDiagnostics.renderRatioP95*100))
                        LabeledContent("Output underrun frames",value:"\(instrument.audioDiagnostics.outputUnderrunFrames)")
                        LabeledContent("Callbacks with underruns",value:"\(instrument.audioDiagnostics.outputUnderrunCallbacks)")
                        LabeledContent("Delivered / requested frames",value:"\(instrument.audioDiagnostics.outputDeliveredFrames) / \(instrument.audioDiagnostics.outputFrames)")
                        LabeledContent("Missing firmware frames",value:"\(instrument.audioDiagnostics.missingFrames)")
                        LabeledContent("Queued audio",value:String(format:"%.1f ms",instrument.audioDiagnostics.bufferedMilliseconds))
                        LabeledContent("Buffer target / maximum",value:String(format:"%.1f / %.1f ms",instrument.audioDiagnostics.lookaheadMilliseconds,instrument.audioDiagnostics.maximumBufferedMilliseconds))
                    } header:{Text("Audio performance")}
                    footer:{Text("Below 100% means the audio engine renders faster than audio plays. Underruns count output frames that had no queued audio; missing firmware frames are counted separately. Buffer duration is not total device latency. Listening and physical-device latency still need separate checks.")}
                    Section("Third-party licenses") {
                        NavigationLink("fm1-emu · MIT") {LicenseNoticeView(title:"fm1-emu",resource:"LICENSE-fm1-emu")}
                        NavigationLink("Native SLOOP · notices & attribution") {LicenseNoticeView(title:"Native SLOOP notices",resource:"NOTICE-native-sloop")}
                        NavigationLink("Native SLOOP · GNU GPL version 3") {LicenseNoticeView(title:"GNU GPL version 3",resource:"LICENSE-native-sloop")}
                    }
                }.navigationTitle("About").toolbar {Button("Done"){about=false}}
            }
        }
        .alert("Couldn’t load firmware",isPresented:Binding(get:{instrument.message != nil},set:{if !$0{instrument.message=nil}})) {Button("OK"){instrument.message=nil}} message:{Text(instrument.message ?? "")}
    }
}

private struct LicenseNoticeView: View {
    let title: String
    let resource: String
    var body: some View {
        ScrollView {
            Text(Bundle.main.url(forResource:resource,withExtension:nil).flatMap {try? String(contentsOf:$0)} ?? "License notice unavailable")
                .font(.caption).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding()
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

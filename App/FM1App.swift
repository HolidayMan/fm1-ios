import SwiftUI
#if FM1_RESEARCH
import WebKit
#endif

@main struct FM1App:App {
    @StateObject private var instrument:Instrument
    init() {
        if let relative=ProcessInfo.processInfo.environment[AppLaunchFixture.environmentKey] {
            let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            let fixture=AppLaunchFixture.resolve(relative,documents:documents)
            let model=Instrument(directory:fixture ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),preferences:UserDefaults(suiteName:"LifecycleUI.\(UUID().uuidString)")!,nativeOnly:true)
            if fixture == nil {model.message="The isolated lifecycle fixture is unavailable."}
            _instrument=StateObject(wrappedValue:model)
        } else {_instrument=StateObject(wrappedValue:Instrument(nativeOnly:true))}
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
                .onAppear {instrument.sceneChanged(active:scenePhase == .active,autoStart:automaticStartupAllowed);ControlHaptics.shared.prepareButton();UIResponsivenessProbe.shared.start()}
                .onChange(of:scenePhase) {phase in
                    instrument.sceneChanged(active:phase == .active,autoStart:automaticStartupAllowed)
                    if phase == .active {ControlHaptics.shared.prepareButton();UIResponsivenessProbe.shared.start()}
                    else {UIResponsivenessProbe.shared.pauseAndWrite()}
                }
        }
    }
}
struct InstrumentView:View {
    @ObservedObject var instrument:Instrument
    @State private var library=false
    @State private var display=false
    @State private var about=false
    @State private var choosingFinish=false
    @State private var projectFiles=false
    @State private var confirmingReset=false
    @State private var resetError:String?
    @State private var resetRecovery:FirmwareResetRecovery?
    @State private var confirmingResetRestore=false
    @AppStorage("panelFinish") private var finishName=PanelFinish.black.rawValue
    @AppStorage("instrumentHeaderCollapsed") private var headerCollapsed=false
    private var finish:PanelFinish {PanelFinish(rawValue:finishName) ?? .black}
    var body:some View {
        UIResponsivenessProbe.shared.measure("InstrumentView.description") {
        GeometryReader {geo in
            // Reuse the landscape side gutter without pushing targets against
            // the physical edge. Recompute after rotation as the insets swap.
            let gutterExtension=min(44,max(0,geo.safeAreaInsets.trailing-12))
            let gutterInset=max(0,12-geo.safeAreaInsets.trailing)
            ZStack(alignment:.topTrailing) {
                VStack(spacing:0) {
                    if !headerCollapsed {topControls.zIndex(1)}
                    PanelView(instrument:instrument,finish:finish,knobReferenceHeight:geo.size.height-32,showScreen:{display=true})
                }.padding(.horizontal,1).padding(.trailing,44-gutterExtension+gutterInset)
                    .frame(width:geo.size.width,height:geo.size.height)
                VStack(spacing:2) {
                    Button {
                        headerCollapsed.toggle();ControlHaptics.shared.button()
                    } label:{
                        Image(systemName:headerCollapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size:16,weight:.semibold))
                            .frame(width:44,height:44).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(finish.accentColor)
                        .accessibilityIdentifier("Toggle top controls")
                        .accessibilityLabel(headerCollapsed ? "Show top controls" : "Hide top controls")
                        .accessibilityValue(headerCollapsed ? "Collapsed" : "Expanded")
                        .accessibilityHint("Firmware, playback, color and information controls")
                    if instrument.supportsProjectFiles {
                    Button {projectFiles=true;ControlHaptics.shared.button()} label:{
                        Image(systemName:"folder").font(.system(size:17,weight:.medium))
                            .frame(width:44,height:44).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(finish.accentColor)
                        .accessibilityIdentifier("Projects and files")
                        .accessibilityLabel("Projects and files")
                    }
                }.padding(.top,16).offset(x:gutterExtension-gutterInset)
            }.frame(width:geo.size.width,height:geo.size.height)
                .background(Color.black)
        }.background {
            // Keep an attached, full-sized WK surface while the native panel draws
            // over it. No browser UI, touch interception or offscreen benchmark.
            #if FM1_RESEARCH
            if !instrument.nativeOnly,let web=instrument.experimentalWebView {WebEngineSurface(webView:web).id(ObjectIdentifier(web)).allowsHitTesting(false).accessibilityHidden(true)}
            #endif
        }.background(Color.black.ignoresSafeArea()).ignoresSafeArea(edges:.bottom).statusBarHidden().persistentSystemOverlays(.hidden).defersSystemGestures(on:.bottom)
        .sheet(isPresented:$library) {FirmwareLibraryView(instrument:instrument)}
        .sheet(isPresented:$projectFiles) {
            ProjectsAndFilesView(instrument:instrument,finish:finish)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented:$choosingFinish) {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                        ForEach(PanelFinish.allCases) {option in
                            Button {finishName=option.rawValue;choosingFinish=false;ControlHaptics.shared.button()} label:{
                                HStack(spacing:12) {
                                    HStack(spacing:0) {Circle().fill(option.swatch).frame(width:28,height:28);Circle().fill(option.secondarySwatch).frame(width:28,height:28).padding(.leading,-10)}
                                    Text(option.rawValue).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Spacer(minLength:0)
                                    Image(systemName:option==finish ? "checkmark.circle.fill" : "circle").foregroundStyle(option==finish ? finish.accentColor : Color.secondary)
                                }.frame(minHeight:44).padding(12)
                                    .background(FM1SurfaceTheme(finish:finish).contentBackground.opacity(0.8),in:RoundedRectangle(cornerRadius:16))
                                    .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(option==finish ? finish.accentColor.opacity(0.6) : Color.clear,lineWidth:1))
                            }.buttonStyle(.plain).accessibilityIdentifier("Finish \(option.rawValue)")
                        }
                    }.padding(16)
                }.navigationTitle("Panel color").navigationBarTitleDisplayMode(.inline).toolbar {Button("Done"){choosingFinish=false}}
                    .background(FM1SurfaceTheme(finish:finish).background)
            }
        }
        .sheet(isPresented:$display) {
            EnlargedDisplayView(frames:instrument.displayState,finish:finish) {display=false}
                .presentationDetents([.large])
        }
        .sheet(isPresented:$about) {
            NavigationStack {
                List {
                    Section("PocketFM") {
                        Text("A touch instrument inspired by the FM-1. Play chords, slide between keys and drag knobs vertically. Tap the display to enlarge it. Use the side arrow to show or hide the top controls.")
                        Text("This independent app is not affiliated with M-VAVE. Panel colors are inspired by the six hardware finishes; screen colors are approximations.")
                    }
                    Section("Playing and saving") {
                        Text("Choose a release from the firmware library. Its download size is shown before you start. Downloads need an internet connection; installed releases can be played offline.")
                        Text("Each release keeps its own saved sounds on this device. Switching releases keeps those saves. Audio pauses when you leave the app or disconnect the audio output.")
                        Text("The top reset button clears only the selected instrument’s work, internal save slots and settings. Save unsaved edits inside the firmware first. To restore saved data from the most recent reset during this session, touch and hold that button. App-library copies and other instruments are kept.")
                            .accessibilityIdentifier("Reset instrument information")
                        if CatalogFirmware.available.contains(where:{$0.id == "hortator"}) {
                            Text("Hortator uses four project slots. Stop playback, open SAVE → PROJECT, choose slot A–D with Knob 1, then turn Knob 4 twice and wait for SAVED before switching instruments or closing. The last saved slot opens next time.")
                                .accessibilityIdentifier("Hortator saving information")
                        }
                    }
                    if CatalogFirmware.available.contains(where:{$0.id == "jiant"}) {
                        Section("JIANT saving") {
                            Text("JIANT starts with Restore Last turned off, as on the device. Enable SYSTEM → RESTORE LAST inside JIANT to resume edited work next time, or save and load projects using JIANT’s own controls.")
                                .accessibilityIdentifier("JIANT saving information")
                        }
                    }
                    if CatalogFirmware.available.contains(where:{$0.id == "official-open"}) {
                        Section("FM1 Open preview") {
                            Text("FM1 Open uses the open-source FM1 Open synthesizer. Its sound can differ from the hardware and the original factory sound bank is not included. This preview keeps its own saved sounds. Older, incompatible saves remain on this device.")
                                .accessibilityIdentifier("FM1 Open preview information")
                        }
                    }
                    Section("Privacy") {
                        Text("Playing and saving happen on this device. No account or microphone access is required. Download requests go to the release hosts, which receive normal connection information such as your IP address. Source links open in your browser.").accessibilityIdentifier("Privacy information")
                        Text("Downloaded files and saved sounds stay in app storage. Deleting the app removes its local files; device backups follow your system settings.")
                        if let privacyPolicyURL {Link("Privacy policy",destination:privacyPolicyURL)}
                    }
                    Section("Credits and licenses") {
                        NavigationLink("fm1-emu · MIT") {LicenseNoticeView(title:"fm1-emu",resource:"LICENSE-fm1-emu",finish:finish)}
                        NavigationLink("SLOOP · credits") {LicenseNoticeView(title:"SLOOP credits",resource:"NOTICE-native-sloop",finish:finish)}
                        NavigationLink("SLOOP · GNU GPL version 3") {LicenseNoticeView(title:"GNU GPL version 3",resource:"LICENSE-native-sloop",finish:finish)}
                        NavigationLink("New instruments · credits") {LicenseNoticeView(title:"Community instrument credits",resource:"NOTICE-native-community",finish:finish)}
                        NavigationLink("New instruments · licenses") {LicenseNoticeView(title:"Community licenses",resource:"LICENSE-native-community",finish:finish)}
                        NavigationLink("New instruments · third-party credits") {LicenseNoticeView(title:"Community third-party credits",resource:"THIRD-PARTY-native-community",finish:finish)}
                        NavigationLink("Firmware authors · credits") {LicenseNoticeView(title:"Firmware credits",resource:"NOTICE-native-family",finish:finish)}
                        NavigationLink("FM1 Open · credits") {LicenseNoticeView(title:"FM1 Open credits",resource:"NOTICE-native-official-preview",finish:finish)}
                        NavigationLink("FM1 Open · license") {LicenseNoticeView(title:"FM1 Open license",resource:"LICENSE-native-official-preview",finish:finish)}
                        NavigationLink("FM1 Open · third-party credits") {LicenseNoticeView(title:"FM1 Open preview credits",resource:"THIRD-PARTY-native-official-preview",finish:finish)}
                        if CatalogFirmware.available.contains(where:{$0.id == "skiff"}) {
                            NavigationLink("Skiff · credits") {LicenseNoticeView(title:"Skiff credits",resource:"NOTICE-native-skiff",finish:finish)}
                            NavigationLink("Skiff · license") {LicenseNoticeView(title:"Skiff license",resource:"LICENSE-native-skiff",finish:finish)}
                            NavigationLink("Skiff · third-party credits") {LicenseNoticeView(title:"Skiff third-party credits",resource:"THIRD-PARTY-native-skiff",finish:finish)}
                        }
                    }
                }.scrollContentBackground(.hidden).background(FM1SurfaceTheme(finish:finish).background)
                    .navigationTitle("About").toolbar {Button("Done"){about=false}}
            }
        }
        .tint(finish.accentColor)
        .alert("Reset current instrument?",isPresented:$confirmingReset) {
            Button("Reset",role:.destructive) {
                ControlHaptics.shared.button()
                Task {
                    do {resetRecovery=try await instrument.resetCurrentFirmware()}
                    catch {resetError=error.localizedDescription}
                }
            }
            Button("Cancel",role:.cancel) {}
        } message: {
            Text("Resets \(instrument.selected?.name ?? "this instrument") to its initial state, including its work, saved slots, sounds and settings. Save unsaved edits inside the firmware first. A recovery copy of saved data is kept. App-library project copies and other instruments are kept.")
        }
        .alert("Restore pre-reset saved data?",isPresented:$confirmingResetRestore) {
            Button("Restore",role:.destructive) {
                guard let recovery=resetRecovery else{return}
                ControlHaptics.shared.button()
                Task {
                    do {try await instrument.restoreFirmwareReset(recovery);resetRecovery=nil}
                    catch {resetError=error.localizedDescription}
                }
            }
            Button("Cancel",role:.cancel) {}
        } message: {
            Text("Replaces this instrument’s current state with saved data from before the last reset. Save any new edits first. A recovery copy of current saved data is kept. Unsaved edits are not restored.")
        }
        .alert("Couldn’t reset instrument",isPresented:Binding(get:{resetError != nil},set:{if !$0 {resetError=nil}})) {
            Button("OK",role:.cancel){resetError=nil}
        } message:{Text(resetError ?? "")}
        .alert("Couldn’t load firmware",isPresented:Binding(get:{instrument.message != nil},set:{if !$0{instrument.message=nil}})) {Button("OK"){instrument.message=nil}} message:{Text(instrument.message ?? "")}
        }
    }
    private var privacyPolicyURL:URL? {
        guard let value=Bundle.main.object(forInfoDictionaryKey:"FM1PrivacyPolicyURL") as? String,
              let url=URL(string:value),url.scheme == "https",url.host != nil else{return nil}
        return url
    }
    private var playbackStatus:String {
        if instrument.busy {return "Loading…"}
        if instrument.running {return "Playing"}
        if instrument.selected == nil {return ""}
        return "Paused"
    }
    private var topControls:some View {
        HStack(spacing:4) {
            Button {library=true;ControlHaptics.shared.button()} label:{
                HStack(spacing:7) {
                    Text(instrument.selected?.name ?? "Choose firmware").lineLimit(1)
                    Image(systemName:"chevron.down").font(.system(size:9,weight:.bold))
                }.font(.system(size:14,weight:.semibold)).offset(y:-4).frame(minHeight:44).contentShape(Rectangle())
            }.accessibilityIdentifier("Firmware library")
            Spacer(minLength:4)
            if instrument.busy {ProgressView().controlSize(.mini).offset(y:-4)}
            Text(playbackStatus).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth:130,alignment:.trailing).offset(y:-4).accessibilityIdentifier("Playback status")
            Button {instrument.playbackWanted ? instrument.pause() : instrument.resume();ControlHaptics.shared.button()} label:{Image(systemName:instrument.playbackWanted ? "pause.fill" : "play.fill").offset(y:-4).frame(width:44,height:44).contentShape(Rectangle())}
                .disabled(instrument.selected == nil || (instrument.busy && !instrument.playbackWanted)).accessibilityLabel(instrument.playbackWanted ? "Pause instrument" : "Resume instrument")
            Button {instrument.toggleMute();ControlHaptics.shared.button()} label:{Image(systemName:instrument.muted ? "speaker.slash" : "speaker.wave.2").offset(y:-4).frame(width:44,height:44).contentShape(Rectangle())}.accessibilityIdentifier("Mute audio").accessibilityLabel(instrument.muted ? "Unmute audio" : "Mute audio").accessibilityValue(instrument.muted ? "Muted" : "Sound on")
            Button {confirmingReset=true;ControlHaptics.shared.button()} label:{
                Image(systemName:"arrow.counterclockwise").offset(y:-4).frame(width:44,height:44).contentShape(Rectangle())
            }.disabled(instrument.selected == nil || instrument.busy)
                .accessibilityIdentifier("Reset instrument").accessibilityLabel("Reset current instrument")
                .accessibilityHint("Reset only this instrument after confirmation. Touch and hold to restore saved data from the last reset in this session")
                .contextMenu {
                    if let recovery=resetRecovery,recovery.firmwareID == instrument.selected?.id {
                        Button("Restore pre-reset saved data…",systemImage:"clock.arrow.circlepath") {confirmingResetRestore=true}
                            .disabled(instrument.busy)
                    }
                }
            Button {choosingFinish=true;ControlHaptics.shared.button()} label:{
                HStack(spacing:0) {Circle().fill(finish.swatch).frame(width:16,height:16);Circle().fill(finish.secondarySwatch).frame(width:16,height:16).padding(.leading,-7)}.offset(y:-4).frame(width:44,height:44).contentShape(Rectangle())
            }.accessibilityLabel("Panel color").accessibilityValue(finish.rawValue)
            Button {about=true;ControlHaptics.shared.button()} label:{Image(systemName:"info.circle").offset(y:-4).frame(width:44,height:44).contentShape(Rectangle())}.accessibilityLabel("About")
        }.buttonStyle(.plain).foregroundStyle(finish.accentColor).tint(finish.accentColor).padding(.horizontal,4).frame(height:44)
            // Keep the 44pt targets; their last 12pt extend into the panel’s
            // noninteractive top rim. The header sits above it for hit testing.
            .frame(height:32,alignment:.top)
    }
}

#if FM1_RESEARCH
private struct WebEngineSurface:UIViewRepresentable {
    let webView:WKWebView
    func makeUIView(context:Context)->WKWebView {webView}
    func updateUIView(_ uiView:WKWebView,context:Context) {}
}

#endif

private struct LicenseNoticeView: View {
    let title: String
    let resource: String
    let finish:PanelFinish
    @State private var notice:String?
    var body: some View {
        ScrollView {
            if let notice {
                Text(notice).font(.caption).textSelection(.enabled).accessibilityIdentifier("License text").frame(maxWidth:.infinity,alignment:.leading).padding()
            } else {ProgressView().padding()}
        }.background(FM1SurfaceTheme(finish:finish).background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task(id:resource) {
            let resource=resource
            let text=await Task.detached(priority:.userInitiated) {
                Bundle.main.url(forResource:resource,withExtension:nil).flatMap {try? String(contentsOf:$0)} ?? "License notice unavailable"
            }.value
            if !Task.isCancelled {notice=text}
        }
    }
}

private struct EnlargedDisplayView:View {
    @ObservedObject var frames:InstrumentDisplayState
    let finish:PanelFinish
    let done:()->Void
    var body:some View {
        VStack(spacing:18) {
            HStack {Text("Display").font(.headline);Spacer();Button("Done",action:done).frame(minWidth:44,minHeight:44)}
                .padding(.horizontal,14).fm1Glass(finish:finish)
            if let image=frames.screen {Image(decorative:image,scale:1).resizable().interpolation(.none).aspectRatio(contentMode:.fit)}
            else {ContentUnavailableView("No instrument playing",systemImage:"display",description:Text("Choose a release from the firmware library to see its display."))}
        }.padding(24).background(FM1SurfaceTheme(finish:finish).background).tint(finish.accentColor)
    }
}

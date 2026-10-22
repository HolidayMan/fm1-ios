import SwiftUI
import AVFoundation

/// Uses the app's playback session. Stopping a preview must not deactivate the synth's session.
@MainActor final class FM1SampleAudition:NSObject,ObservableObject,AVAudioPlayerDelegate {
    @Published private(set) var playing=false
    @Published private(set) var errorMessage:String?
    private var player:AVAudioPlayer?
    private var observations=[NSObjectProtocol]()
    var currentTime:Double {player?.currentTime ?? 0}
    var duration:Double {player?.duration ?? 0}
    override init() {
        super.init()
        for name in [AVAudioSession.interruptionNotification,AVAudioSession.routeChangeNotification,AVAudioSession.mediaServicesWereResetNotification] {
            observations.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                let stop:Bool
                if name == AVAudioSession.interruptionNotification {
                    stop=(note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
                } else if name == AVAudioSession.routeChangeNotification {
                    stop=(note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                } else {stop=true}
                if stop {Task {@MainActor in self?.stop()}}
            })
        }
    }
    deinit {for token in observations {NotificationCenter.default.removeObserver(token)}}
    func play(_ data:Data)throws {
        stop();errorMessage=nil
        let session=AVAudioSession.sharedInstance()
        try session.setCategory(.playback,mode:.default,options:[])
        try session.setActive(true)
        let audio=try AVAudioPlayer(data:data,fileTypeHint:AVFileType.wav.rawValue)
        audio.delegate=self
        guard audio.prepareToPlay() else {throw failure("The selected region could not be prepared for playback.")}
        // Retain before play: a fast completion must never leave a stale player retained.
        player=audio
        guard audio.play() else {stop();throw failure("The selected region could not be played. Try again after audio playback is available.")}
        playing=true
    }
    func stop(){player?.stop();player=nil;playing=false}
    private func failure(_ message:String)->NSError {NSError(domain:"FM1Sample",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    nonisolated func audioPlayerDidFinishPlaying(_ audio:AVAudioPlayer,successfully flag:Bool) {
        Task {@MainActor in
            guard self.player === audio else{return}
            self.stop()
            if !flag {self.errorMessage="Audio playback stopped before the preview finished."}
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ audio:AVAudioPlayer,error:Error?) {
        let message=error?.localizedDescription ?? "The preview audio could not be decoded."
        Task {@MainActor in
            guard self.player === audio else{return}
            self.stop();self.errorMessage=message
        }
    }
}

@MainActor struct FM1SampleTrimView:View {
    let source:SampleAudioSource
    let waveform:[Float]
    let finish:PanelFinish
    let apply:(Data,Int,String,Int?)async throws->Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var audition=FM1SampleAudition()
    @State private var selection:SampleTrimSelection
    @State private var visibleRange:Range<Int>
    @State private var visibleWaveform:[Float]
    @State private var slot=0
    @State private var track=0
    @State private var normalize=false
    @State private var preparing=false
    @State private var committing=false
    @State private var confirming=false
    @State private var errorText:String?
    @State private var previewTask:Task<Void,Never>?
    @State private var previewID=UUID()
    init(source:SampleAudioSource,waveform:[Float],finish:PanelFinish,apply:@escaping(Data,Int,String,Int?)async throws->Void) {
        self.source=source;self.waveform=waveform;self.finish=finish;self.apply=apply
        _selection=State(initialValue:SampleTrimSelection(frameCount:source.samples.count))
        let range=0..<min(source.samples.count,SampleAudioImporter.maximumFrames*6/5)
        _visibleRange=State(initialValue:range)
        _visibleWaveform=State(initialValue:source.waveform(in:range))
    }
    private var theme:FM1SurfaceTheme {FM1SurfaceTheme(finish:finish)}
    private var overview:Bool {visibleRange.count == source.samples.count && source.samples.count>SampleAudioImporter.maximumFrames}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text(source.name).font(.title3.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
                    Text("Drag the handles to keep one region. Preview plays the converted sound, including normalization.").font(.callout).foregroundStyle(.secondary)
                    TimelineView(.animation(minimumInterval:1.0/30,paused:!audition.playing)) { _ in
                        FM1SampleWaveform(values:visibleWaveform,visibleRange:visibleRange,overview:overview,selection:$selection,playhead:audition.playing ? (selection.start+audition.currentTime)/max(source.duration,1.0/22050) : nil,onEdit:stopPreview)
                            .foregroundStyle(theme.accent).frame(height:136)
                    }
                    Button(visibleRange.count == source.samples.count ? "Zoom to selection" : "Show full recording") {toggleZoom()}
                        .frame(minHeight:44).accessibilityIdentifier("Sample waveform zoom")
                    if overview {
                        Text("Full recording: tap or drag to move the selected region. Zoom to selection to trim its handles.").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("\(selection.start,format:.number.precision(.fractionLength(2))) – \(selection.end,format:.number.precision(.fractionLength(2))) s")
                        Spacer()
                        Text("\(selection.end-selection.start,format:.number.precision(.fractionLength(2))) s selected")
                    }.font(.callout.monospacedDigit()).accessibilityElement(children:.combine).accessibilityIdentifier("Selected sample region")
                    Button {preview()} label:{
                        Label(audition.playing ? "Stop preview" : preparing ? "Preparing preview…" : "Play preview",systemImage:audition.playing ? "stop.fill" : "play.fill")
                            .frame(minHeight:44).frame(maxWidth:.infinity).padding(.horizontal,14)
                            .fm1Glass(finish:finish,cornerRadius:14,interactive:true)
                    }.buttonStyle(.plain).disabled(committing || preparing || !selection.fits).accessibilityIdentifier("Audition sample")
                    Text("\(Double(selection.encodedBytes)/1024,specifier:"%.1f") KiB / 80 KiB after encoding")
                        .font(.callout.monospacedDigit()).foregroundStyle(selection.fits ? Color.secondary : .orange)
                        .accessibilityIdentifier("Encoded sample capacity")
                    if !selection.fits {
                        Button("Fit from start (up to \(SampleAudioImporter.maximumDuration,format:.number.precision(.fractionLength(2))) s)") {stopPreview();selection.fit()}
                            .frame(minHeight:44).accessibilityIdentifier("Fit sample region")
                    }
                    DisclosureGroup("Precise times") {
                        HStack {
                            Text("Start")
                            TextField("Start time",value:Binding(get:{selection.start},set:{stopPreview();selection.setStart(fraction:$0/source.duration)}),format:.number.precision(.fractionLength(3)))
                                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(minHeight:44)
                            Text("End")
                            TextField("End time",value:Binding(get:{selection.end},set:{stopPreview();selection.setEnd(fraction:$0/source.duration)}),format:.number.precision(.fractionLength(3)))
                                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(minHeight:44)
                        }
                    }
                    Toggle("Normalize selected region",isOn:$normalize).frame(minHeight:44).onChange(of:normalize){_,_ in stopPreview()}
                    Text("22.05 kHz · mono · one instrument zone · original audio unchanged").font(.caption).foregroundStyle(.secondary)
                    Picker("USR slot",selection:$slot) {ForEach(0..<4){Text("USR\($0+1)").tag($0)}}
                        .pickerStyle(.segmented).frame(minHeight:44).accessibilityIdentifier("Sample destination")
                    Picker("Play on",selection:$track) {
                        ForEach(0..<3){Text("Track \($0+1)").tag($0)}
                        Text("Slot only").tag(-1)
                    }.pickerStyle(.segmented).frame(minHeight:44).accessibilityIdentifier("Sample track")
                    Text(track>=0 ? "Track \(track+1) will use SAMPLE → SET → USR\(slot+1). Play C4 to hear the original pitch; other notes transpose it." : "To play later: choose SAMPLE → SET → USR\(slot+1), or GRAIN → SRC → USR\(slot+1).")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Replaces the shared slot in the current workspace. Tracks and sections using it will play the new sound. A recovery backup is saved first; named copies stay unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {stopPreview();confirming=true} label:{
                        if committing {ProgressView().frame(minHeight:44).frame(maxWidth:.infinity)}
                        else {Label("Add to USR\(slot+1)…",systemImage:"square.and.arrow.down").frame(minHeight:44).frame(maxWidth:.infinity)}
                    }.buttonStyle(.borderedProminent).disabled(!selection.fits || committing || preparing).accessibilityIdentifier("Apply sample")
                }.padding(20).frame(maxWidth:720).frame(maxWidth:.infinity).disabled(committing)
            }.background(theme.background).tint(theme.accent)
                .navigationTitle("Trim sample").navigationBarTitleDisplayMode(.inline)
                .toolbar {Button("Cancel"){stopPreview();dismiss()}.disabled(committing)}
                .interactiveDismissDisabled(committing)
                .onDisappear {stopPreview()}
                .onChange(of:scenePhase){_,phase in if phase != .active {stopPreview()}}
                .onReceive(audition.$errorMessage){if let message=$0 {errorText=message}}
                .confirmationDialog("Replace the sound in USR\(slot+1)?",isPresented:$confirming,titleVisibility:.visible) {
                    Button("Back up and replace",role:.destructive){commit()}
                    Button("Cancel",role:.cancel){}
                } message:{Text("A recovery backup is saved before replacing the slot\(track>=0 ? " and assigning Track \(track+1)" : ""). Named saved copies stay unchanged.")}
                .alert("Sample action failed",isPresented:Binding(get:{errorText != nil},set:{if !$0 {errorText=nil}})) {Button("OK",role:.cancel){}} message:{Text(errorText ?? "")}
        }
    }
    private func toggleZoom() {
        stopPreview()
        if visibleRange.count == source.samples.count {
            let padding=max(1,selection.count/8)
            visibleRange=max(0,selection.first-padding)..<min(source.samples.count,selection.last+padding)
        } else {visibleRange=0..<source.samples.count}
        visibleWaveform=source.waveform(in:visibleRange)
    }
    private func stopPreview() {
        previewID=UUID();previewTask?.cancel();previewTask=nil;preparing=false;audition.stop()
    }
    private func preview() {
        if audition.playing {stopPreview();return}
        stopPreview();let id=previewID,selection=selection,normalize=normalize
        preparing=true
        previewTask=Task {
            do {
                let data=try await Task.detached(priority:.userInitiated){try SampleAudioImporter.previewWAV(source:source,start:selection.start,end:selection.end,normalize:normalize)}.value
                guard !Task.isCancelled,id==previewID,scenePhase == .active else{return}
                preparing=false;try audition.play(data)
            } catch {if !Task.isCancelled,id==previewID {preparing=false;errorText=error.localizedDescription}}
        }
    }
    private func commit() {
        stopPreview();let selection=selection,normalize=normalize,destination=slot,target=track
        committing=true
        Task {
            defer {committing=false}
            do {
                let data=try await Task.detached(priority:.userInitiated){try SampleAudioImporter.encode(source:source,start:selection.start,end:selection.end,normalize:normalize)}.value
                try await apply(data,destination,source.name,target>=0 ? target : nil)
                dismiss()
            } catch {errorText=error.localizedDescription}
        }
    }
}

private struct FM1SampleWaveform:View {
    let values:[Float]
    let visibleRange:Range<Int>
    let overview:Bool
    @Binding var selection:SampleTrimSelection
    let playhead:Double?
    let onEdit:()->Void
    @State private var dragMode:Int?
    @State private var dragFirst=0
    var body:some View {
        GeometryReader {geometry in
            let width=max(1,geometry.size.width-44)
            let start=Double(selection.first-visibleRange.lowerBound)/Double(visibleRange.count),end=Double(selection.last-visibleRange.lowerBound)/Double(visibleRange.count)
            ZStack(alignment:.leading) {
                Canvas {context,size in
                    var bars=Path()
                    for (index,value) in values.enumerated() {
                        let x=22+CGFloat(index)*width/CGFloat(max(1,values.count-1))
                        let amplitude=CGFloat(min(1,max(0,abs(value))))*(size.height-28)/2
                        bars.move(to:CGPoint(x:x,y:size.height/2-amplitude));bars.addLine(to:CGPoint(x:x,y:size.height/2+amplitude))
                    }
                    context.stroke(bars,with:.foreground,lineWidth:2)
                    context.fill(Path(CGRect(x:22,y:0,width:width*max(0,min(1,start)),height:size.height)),with:.color(.black.opacity(0.4)))
                    context.fill(Path(CGRect(x:22+width*max(0,min(1,end)),y:0,width:width*(1-max(0,min(1,end))),height:size.height)),with:.color(.black.opacity(0.4)))
                    let selected=CGRect(x:22+width*max(0,start),y:0,width:width*max(0,min(1,end)-max(0,start)),height:size.height)
                    context.stroke(Path(selected),with:.foreground,lineWidth:2)
                    if let playhead {
                        var line=Path();let x=22+width*(playhead*Double(selection.frameCount)-Double(visibleRange.lowerBound))/Double(visibleRange.count)
                        line.move(to:CGPoint(x:x,y:0));line.addLine(to:CGPoint(x:x,y:size.height))
                        context.stroke(line,with:.color(.primary),lineWidth:2)
                    }
                }.accessibilityHidden(true)
                handle(start:true).opacity(start>=0 && start<=1 ? 1 : 0).position(x:22+width*start,y:geometry.size.height/2)
                handle(start:false).opacity(end>=0 && end<=1 ? 1 : 0).position(x:22+width*end,y:geometry.size.height/2)
            }.background(.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:8))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged {value in
                    if dragMode == nil {
                        let x=value.startLocation.x,left=22+width*start,right=22+width*end
                        if overview {
                            dragMode=0
                            let center=visibleRange.lowerBound+Int(Double((x-22)/width)*Double(visibleRange.count))
                            selection.move(first:center-selection.count/2)
                        } else {dragMode=(x>left+22 && x<right-22) ? 0 : abs(x-left)<abs(x-right) ? -1 : 1}
                        dragFirst=selection.first;onEdit()
                    }
                    let fraction=(Double(visibleRange.lowerBound)+Double((value.location.x-22)/width)*Double(visibleRange.count))/Double(selection.frameCount)
                    if dragMode == -1 {selection.setStart(fraction:fraction)}
                    else if dragMode == 1 {selection.setEnd(fraction:fraction)}
                    else {selection.move(first:dragFirst+Int((Double(value.translation.width/width)*Double(visibleRange.count)).rounded()))}
                }.onEnded {_ in dragMode=nil})
                .clipped()

        }.accessibilityIdentifier("Sample trim waveform")
    }
    private func handle(start:Bool)->some View {
        ZStack {
            RoundedRectangle(cornerRadius:5).frame(width:12)
            Capsule().fill(.background).frame(width:3,height:24)
        }.frame(width:44).contentShape(Rectangle())
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(start ? "Sample start" : "Sample end")
            .accessibilityValue("\(start ? selection.start : selection.end,format:.number.precision(.fractionLength(2))) seconds")
            .accessibilityAdjustableAction {direction in
                onEdit()
                let delta=Double(direction == .increment ? 1 : -1)*Double(SampleAudioImporter.sampleRate)/10/Double(selection.frameCount)
                if start {selection.setStart(fraction:Double(selection.first)/Double(selection.frameCount)+delta)}
                else {selection.setEnd(fraction:Double(selection.last)/Double(selection.frameCount)+delta)}
            }
            .accessibilityIdentifier(start ? "Sample trim start handle" : "Sample trim end handle")
    }
}

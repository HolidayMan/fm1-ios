import UIKit
import QuartzCore

/// Opt-in local profiling only. Frame intervals describe this app's display-link
/// delivery, not a calibrated device latency or an Instruments hitch verdict.
final class UIResponsivenessProbe:NSObject {
    static let shared=UIResponsivenessProbe()
    private var link:CADisplayLink?
    private var intervals:[Double]=[]
    private var expected:[Double]=[]
    private var last:CFTimeInterval?
    private var started:CFTimeInterval=0
    private struct Operation {var count=0;var totalMs=0.0;var maximumMs=0.0}
    private var operations:[String:Operation]=[:]
    private let storage=DispatchQueue(label:"fm1.ui-profile-storage",qos:.utility)
    private let enabled=ProcessInfo.processInfo.environment["FM1_PROFILE_UI"] == "1"
    private override init() {super.init()}
    func measure<T>(_ name:String,_ work:()->T)->T {
        guard enabled,Thread.isMainThread else{return work()}
        let began=CACurrentMediaTime()
        defer {record(name,began:began)}
        return work()
    }
    func beginOperation()->CFTimeInterval? {enabled && Thread.isMainThread ? CACurrentMediaTime() : nil}
    func record(_ name:String,began:CFTimeInterval?) {
        guard let began else{return}
        let elapsed=(CACurrentMediaTime()-began)*1000
        var value=operations[name] ?? Operation()
        value.count += 1;value.totalMs += elapsed;value.maximumMs=max(value.maximumMs,elapsed)
        operations[name]=value
    }
    func start() {
        guard enabled,link == nil else{return}
        if started == 0 {started=CACurrentMediaTime()}
        last=nil
        let link=CADisplayLink(target:self,selector:#selector(frame(_:)))
        link.add(to:.main,forMode:.common);self.link=link
    }
    @objc private func frame(_ link:CADisplayLink) {
        if let last,intervals.count < 100_000 {
            intervals.append(link.timestamp-last)
            expected.append(max(0.001,link.targetTimestamp-link.timestamp))
        }
        last=link.timestamp
    }
    func pauseAndWrite() {
        guard enabled else{return}
        link?.invalidate();link=nil;last=nil
        let ordered=intervals.sorted(),count=ordered.count
        let delayed=zip(intervals,expected).filter {$0.0 > $0.1*1.5}.count
        let timings=operations.mapValues {value->[String:Any] in
            ["count":value.count,"totalMs":value.totalMs,"maximumMs":value.maximumMs]
        }
        let report:[String:Any]=[
            "operations":timings,
            "scope":"foreground-display-link-delivery",
            "frameIntervals":count,
            "elapsedSeconds":started == 0 ? 0 : CACurrentMediaTime()-started,
            "meanFrameIntervalMs":count == 0 ? 0 : intervals.reduce(0,+)/Double(count)*1000,
            "p95FrameIntervalMs":count == 0 ? 0 : ordered[min(count-1,Int(Double(count)*0.95))]*1000,
            "maximumFrameIntervalMs":(ordered.last ?? 0)*1000,
            "intervalsOverOneAndHalfFrames":delayed,
            "nominalFrameIntervalMs":expected.isEmpty ? 0 : expected.reduce(0,+)/Double(expected.count)*1000,
            "note":"Includes normal launch/sheet animation and debugger/simulator scheduling; no physical latency claim."
        ]
        storage.async {
            guard let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),
                  let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else{return}
            let folder=documents.appendingPathComponent("PerformanceReports",isDirectory:true)
            do {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try data.write(to:folder.appendingPathComponent("menu-responsiveness.json"),options:.atomic)
            } catch {} // A probe never changes playback policy or reports user errors.
        }
    }
}

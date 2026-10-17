import Foundation

/// Main-thread intent; temporary scene loss never becomes a manual pause.
struct PlaybackPolicy {
    private(set) var appeared=false
    private(set) var requested=false
    private(set) var manuallyPaused=false
    private(set) var sceneActive=true
    private(set) var interrupted=false
    private(set) var blocked=false
    var wantsPlayback:Bool {requested && !manuallyPaused && !blocked}
    var shouldRun:Bool {wantsPlayback && sceneActive && !interrupted}
    mutating func scene(active:Bool,autoStart:Bool)->Bool {
        let changed = !appeared || sceneActive != active
        if !appeared {requested = requested || autoStart;appeared=true}
        sceneActive=active;return changed
    }
    mutating func play() {requested=true;manuallyPaused=false;blocked=false}
    mutating func pause() {manuallyPaused=true}
    mutating func interruptionBegan() {interrupted=true}
    mutating func interruptionEnded(shouldResume:Bool) {interrupted=false;if !shouldResume {blocked=true}}
    mutating func hold() {blocked=true}
}

/// Only the worker reads this gate. No lock is taken by the audio callback.
final class PlaybackDemand {
    private let lock=NSLock()
    private var desired=false,failed=false
    private var retryEpoch=0
    func set(_ value:Bool) {lock.lock();desired=value;lock.unlock()}
    func clearFailure() {lock.lock();retryEpoch += 1;failed=false;lock.unlock()}
    var epoch:Int {lock.lock();defer{lock.unlock()};return retryEpoch}
    @discardableResult func fail(epoch:Int)->Bool {
        lock.lock();defer{lock.unlock()}
        guard epoch == retryEpoch else{return false}
        failed=true;return true
    }
    var shouldRun:Bool {lock.lock();defer{lock.unlock()};return desired && !failed}
}

/// Opt-in UI-test fixture; never redirects a malformed path to the owner's library.
enum AppLaunchFixture {
    static let environmentKey="FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY"
    static func resolve(_ relative:String,documents:URL)->URL? {
        let parts=relative.split(separator:"/",omittingEmptySubsequences:false).map(String.init)
        guard parts.count >= 3,parts[0] == "Documents",parts[1] == "PerformanceFixtures",
              parts.allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}) else{return nil}
        let root=documents.resolvingSymlinksInPath().appendingPathComponent("PerformanceFixtures",isDirectory:true)
        let url=parts.dropFirst().reduce(documents){$0.appendingPathComponent($1,isDirectory:true)}.resolvingSymlinksInPath()
        var directory:ObjCBool=false
        guard url.path.hasPrefix(root.path+"/"),FileManager.default.fileExists(atPath:url.path,isDirectory:&directory),directory.boolValue else{return nil}
        return url
    }
}

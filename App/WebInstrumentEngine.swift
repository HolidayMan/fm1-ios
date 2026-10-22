#if FM1_RESEARCH
import Foundation
import WebKit
import Network

/// A narrow instance boundary also permits deterministic storage/rollback tests
/// without starting a browser, audio device or unrelated firmware execution.
protocol WebEngineHosting:AnyObject {
    var identity:UUID {get}
    var presentationView:WKWebView? {get}
    var onSnapshot:(([String:Any])->Void)? {get set}
    var onDiagnostics:(([String:Any])->Void)? {get set}
    var onCheckpoint:((Data)->Void)? {get set}
    var onFailure:((Error)->Void)? {get set}
    func load(package:Data,flash:Data?,moduleSHA256:String)throws
    func load(package:Data,flash:Data?,moduleSHA256:String,guestMHz:Int)throws
    func command(_ op:String,values:[String:Any],timeout:TimeInterval)throws->[String:Any]
    func startCheckpoints()
    func pause()throws->Data
    func close()
}
extension WebEngineHosting {
    func load(package:Data,flash:Data?,moduleSHA256:String,guestMHz:Int)throws {
        guard guestMHz == 240 else {throw WebInstrumentEngine.failure("This engine does not support the selected clock.")}
        try load(package:package,flash:flash,moduleSHA256:moduleSHA256)
    }
    @discardableResult func request(_ op:String,values:[String:Any]=[:],timeout:TimeInterval=15)throws->[String:Any] {try command(op,values:values,timeout:timeout)}
}


/// Read-only, token-scoped HTTP origin. Only the loopback interface is bound;
/// no directory listing, owner files, network proxy or writable route exists.
private final class WebEngineOrigin {
    private let queue=DispatchQueue(label:"fm1.web-origin")
    private var listener:NWListener?
    private let package:Data,flash:Data?
    private let token=UUID().uuidString.replacingOccurrences(of:"-",with:"")
    private var connections:[ObjectIdentifier:NWConnection]=[:]
    init(package:Data,flash:Data?) {self.package=package;self.flash=flash}
    func start()throws->URL {
        let parameters=NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        let next=try NWListener(using:parameters)
        let ready=DispatchSemaphore(value:0)
        var outcome:Result<URL,Error>?
        next.stateUpdateHandler={ [weak self,weak next] state in
            guard let self else{return}
            switch state {
            case .ready:
                if let port=next?.port {outcome = .success(URL(string:"http://127.0.0.1:\(port.rawValue)/\(self.token)/")!);ready.signal()}
            case .failed(let error):outcome = .failure(error);ready.signal()
            default:break
            }
        }
        next.newConnectionHandler={ [weak self] connection in
            guard let self else {connection.cancel();return}
            let key=ObjectIdentifier(connection);self.connections[key]=connection
            connection.start(queue:self.queue)
            self.receive(connection,key:key,buffer:Data())
        }
        listener=next;next.start(queue:queue)
        guard ready.wait(timeout:.now()+10) == .success,let outcome else {next.cancel();throw WebInstrumentEngine.failure("The local audio origin did not start.")}
        return try outcome.get()
    }
    private func receive(_ connection:NWConnection,key:ObjectIdentifier,buffer:Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:8192) { [weak self] bytes,_,complete,error in
            guard let self else {connection.cancel();return}
            var request=buffer;if let bytes {request.append(bytes)}
            guard request.count <= 16384 else {self.finish(connection,key:key,status:"431 Request Header Fields Too Large",data:Data(),type:"text/plain");return}
            if request.range(of:Data("\r\n\r\n".utf8)) != nil {
                self.respond(connection,key:key,request:request)
            } else if error != nil || complete {connection.cancel();self.connections.removeValue(forKey:key)}
            else {self.receive(connection,key:key,buffer:request)}
        }
    }
    private func respond(_ connection:NWConnection,key:ObjectIdentifier,request:Data) {
        guard let text=String(data:request,encoding:.utf8),let line=text.components(separatedBy:"\r\n").first else {connection.cancel();connections.removeValue(forKey:key);return}
        let words=line.split(separator:" ")
        guard words.count == 3,words[0] == "GET" else {finish(connection,key:key,status:"405 Method Not Allowed",data:Data(),type:"text/plain");return}
        let path=String(words[1]).components(separatedBy:"?")[0]
        let prefix="/\(token)/"
        guard path.hasPrefix(prefix) else {finish(connection,key:key,status:"404 Not Found",data:Data(),type:"text/plain");return}
        let resource=String(path.dropFirst(prefix.count))
        let allowed=["index.html","host.js","engine-worker.js","pcm-worklet.js","engine.wasm","engine.js"]
        var bytes:Data?,type="application/octet-stream"
        if resource == "package.fwsc" {bytes=package}
        else if resource == "initial.flash" {bytes=flash}
        else if allowed.contains(resource),let root=Bundle.main.resourceURL {
            let nested=root.appendingPathComponent("WebEngine",isDirectory:true).appendingPathComponent(resource)
            bytes=(try? Data(contentsOf:nested)) ?? (try? Data(contentsOf:root.appendingPathComponent(resource)))
            if resource.hasSuffix(".html") {type="text/html; charset=utf-8"}
            else if resource.hasSuffix(".js") {type="text/javascript; charset=utf-8"}
            else if resource.hasSuffix(".wasm") {type="application/wasm"}
        }
        finish(connection,key:key,status:bytes == nil ? "404 Not Found" : "200 OK",data:bytes ?? Data(),type:type)
    }
    private func finish(_ connection:NWConnection,key:ObjectIdentifier,status:String,data:Data,type:String) {
        let headers="HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nCross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: require-corp\r\nCross-Origin-Resource-Policy: same-origin\r\nContent-Security-Policy: default-src 'self' blob:; script-src 'self' 'wasm-unsafe-eval' blob:; worker-src 'self' blob:; connect-src 'self'; style-src 'unsafe-inline'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'\r\nConnection: close\r\n\r\n"
        var response=Data(headers.utf8);response.append(data)
        connection.send(content:response,completion:.contentProcessed { [weak self] _ in
            connection.cancel();self?.queue.async {self?.connections.removeValue(forKey:key)}
        })
    }
    func close() {queue.async { [self] in listener?.cancel();listener=nil;for connection in connections.values {connection.cancel()};connections.removeAll()}}
    deinit {listener?.cancel()}
}

/// WK APIs are main-thread only. Bounded waits belong to Instrument's serial
/// worker; no Swift work or emulator enters an AudioWorklet render callback.
final class WebInstrumentEngine:NSObject,WKScriptMessageHandler,WKNavigationDelegate,WebEngineHosting {
    let identity=UUID()
    let webView:WKWebView
    var presentationView:WKWebView? {webView}
    private var origin:WebEngineOrigin?
    private var baseURL:URL?
    private var nextID=0
    private var replies:[Int:(Result<[String:Any],Error>)->Void]=[:]
    private var readyReply:((Result<Void,Error>)->Void)?
    private var closed=false
    private var checkpointTimer:Timer?
    private var checkpointPending=false
    var onSnapshot:(([String:Any])->Void)?
    var onDiagnostics:(([String:Any])->Void)?
    var onCheckpoint:((Data)->Void)?
    var onFailure:((Error)->Void)?
    static func failure(_ message:String)->NSError {NSError(domain:"FM1.WebEngine",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    static func make()throws->WebInstrumentEngine {
        precondition(!Thread.isMainThread)
        let ready=DispatchSemaphore(value:0)
        var engine:WebInstrumentEngine?
        DispatchQueue.main.async {engine=WebInstrumentEngine();ready.signal()}
        guard ready.wait(timeout:.now()+10) == .success,let engine else {throw failure("Could not prepare the experimental audio view.")}
        return engine
    }
    override init() {
        let configuration=WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback=true
        configuration.mediaTypesRequiringUserActionForPlayback=[]
        webView=WKWebView(frame:.zero,configuration:configuration)
        super.init()
        webView.isOpaque=false;webView.backgroundColor = .black
        webView.isUserInteractionEnabled=false
        webView.navigationDelegate=self
        configuration.userContentController.add(self,name:"fm1")
    }
    /// Called from the Instrument worker after the main-thread view is attached.
    func load(package:Data,flash:Data?,moduleSHA256:String)throws {
        try load(package:package,flash:flash,moduleSHA256:moduleSHA256,guestMHz:240)
    }
    func load(package:Data,flash:Data?,moduleSHA256:String,guestMHz:Int)throws {
        guard EmulatorClock.allowedMHz.contains(guestMHz) else {throw Self.failure("Unsupported emulation clock.")}
        let server=WebEngineOrigin(package:package,flash:flash)
        let base=try server.start();origin=server;baseURL=base
        try wait(timeout:20) { completion in
            self.readyReply=completion
            self.webView.load(URLRequest(url:base.appendingPathComponent("index.html"),cachePolicy:.reloadIgnoringLocalCacheData))
        }
        _=try command("load",values:["packageURL":base.appendingPathComponent("package.fwsc").absoluteString,
                                     "flashURL":flash == nil ? NSNull() : base.appendingPathComponent("initial.flash").absoluteString as Any,
                                     "expectedModuleSHA256":moduleSHA256,"sampleRate":44100,"guestHz":guestMHz*1000000],timeout:45)
    }
    private func wait<T>(timeout:TimeInterval,action:@escaping (@escaping (Result<T,Error>)->Void)->Void)throws->T {
        precondition(!Thread.isMainThread,"Web engine waits must stay on the instrument worker")
        let semaphore=DispatchSemaphore(value:0),lock=NSLock()
        var result:Result<T,Error>?
        DispatchQueue.main.async {action {value in lock.lock();if result == nil {result=value;semaphore.signal()};lock.unlock()}}
        guard semaphore.wait(timeout:.now()+timeout) == .success else {throw Self.failure("Experimental WASM timed out. Your saved sounds have been retained; switch back to a native engine to continue.")}
        lock.lock();defer{lock.unlock()};return try result!.get()
    }
    @discardableResult func command(_ op:String,values:[String:Any]=[:],timeout:TimeInterval=15)throws->[String:Any] {
        try wait(timeout:timeout+1) {completion in self.send(op,values:values,timeout:timeout,completion:completion)}
    }
    private func send(_ op:String,values:[String:Any]=[:],timeout:TimeInterval=15,completion:@escaping(Result<[String:Any],Error>)->Void) {
        guard !closed else {completion(.failure(Self.failure("The experimental engine is closed.")));return}
        nextID += 1;let id=nextID
        var payload=values;payload["id"]=id;payload["op"]=op
        guard let data=try? JSONSerialization.data(withJSONObject:payload),let json=String(data:data,encoding:.utf8) else {completion(.failure(Self.failure("Invalid experimental engine command.")));return}
        replies[id]=completion
        DispatchQueue.main.asyncAfter(deadline:.now()+timeout) { [weak self] in
            self?.replies.removeValue(forKey:id)?(.failure(Self.failure("Experimental WASM \(op) timed out. Your previous checkpoint is retained.")))
        }
        webView.evaluateJavaScript("window.FM1Host.command(\(json)); null") { [weak self] _,error in
            if let error {self?.replies.removeValue(forKey:id)?(.failure(error))}
        }
    }
    func startCheckpoints() {DispatchQueue.main.async { [weak self] in
        guard let self,!self.closed else{return}
        self.checkpointTimer?.invalidate()
        self.checkpointTimer=Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in
            guard let self,!self.checkpointPending else{return}
            self.checkpointPending=true
            self.send("flash",timeout:10) { [weak self] result in
                self?.checkpointPending=false
                if case .success(let reply)=result,let encoded=reply["flash"] as? String,let bytes=Data(base64Encoded:encoded),bytes.count == 1<<20 {self?.onCheckpoint?(bytes)}
            }
        }
    }}
    func pause()throws->Data {
        DispatchQueue.main.async { [weak self] in self?.checkpointTimer?.invalidate();self?.checkpointTimer=nil}
        let reply=try command("pause")
        guard let text=reply["flash"] as? String,let flash=Data(base64Encoded:text),flash.count == 1<<20 else {throw Self.failure("Experimental WASM did not return a complete saved-sounds snapshot. The existing files are retained.")}
        if let diagnostics=reply["diagnostics"] as? [String:Any] {DispatchQueue.main.async {self.onDiagnostics?(diagnostics)}}
        return flash
    }
    func close() {
        // Closing the page terminates its Worker too; first ask the live host to
        // disconnect and close its AudioContext, bounded if the process has hung.
        if !Thread.isMainThread {_=try? command("close",timeout:3)}
        origin?.close();origin=nil
        DispatchQueue.main.async { [self] in
            guard !closed else{return};closed=true;checkpointTimer?.invalidate();checkpointTimer=nil
            webView.stopLoading();webView.configuration.userContentController.removeScriptMessageHandler(forName:"fm1")
            webView.navigationDelegate=nil
            webView.loadHTMLString("",baseURL:nil)
            let pending=replies.values;replies.removeAll()
            for completion in pending {completion(.failure(Self.failure("The experimental engine was closed.")))}
            readyReply?(.failure(Self.failure("The experimental engine was closed.")));readyReply=nil
        }
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard !closed,message.frameInfo.isMainFrame,let body=message.body as? [String:Any],let kind=body["kind"] as? String else{return}
        switch kind {
        case "ready":readyReply?(.success(()));readyReply=nil
        case "reply":
            guard let id=body["id"] as? Int,let completion=replies.removeValue(forKey:id) else{return}
            if body["ok"] as? Bool == true {completion(.success(body["result"] as? [String:Any] ?? [:]))}
            else {completion(.failure(Self.failure(body["error"] as? String ?? "Experimental WASM failed.")))}
        case "snapshot":onSnapshot?(body)
        case "diagnostics":
            #if DEBUG
            if let stage=body["stage"] as? String {NSLog("Experimental engine stage: %@",stage)}
            #endif
            onDiagnostics?(body)
        case "failure":onFailure?(Self.failure(body["error"] as? String ?? "Experimental WASM failed."))
        default:break
        }
    }
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {readyReply?(.failure(error));readyReply=nil;onFailure?(error)}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {readyReply?(.failure(error));readyReply=nil;onFailure?(error)}
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) {onFailure?(Self.failure("The experimental web audio process stopped. Your previous checkpoint remains available; switch back to a native engine to continue."))}
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url=navigationAction.request.url,let base=baseURL,url.scheme == base.scheme,url.host == base.host,url.port == base.port,url.path.hasPrefix(base.path) else {decisionHandler(.cancel);return}
        decisionHandler(.allow)
    }
}

#endif

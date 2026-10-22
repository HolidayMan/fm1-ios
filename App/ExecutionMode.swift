import Foundation

// Legacy mode identifiers remain readable so separate research saves stay intact.
enum SloopExecutionMode:String,CaseIterable,Identifiable {
    case native,wasm
    var id:String {rawValue}
    var title:String {self == .native ? "Native" : "Universal WASM"}
    static let preferenceKey="sloopExecutionMode"
    static let packageSHA256="fb69b4311790eb7ec09498be16ae2b71bd681840e221c0d8cfdb26fb5f9a2928"
    static let moduleSHA256="d3f51e1b50fd90c5be186f592c52a04139faceb5fbefd41c248790e620620c87"
}


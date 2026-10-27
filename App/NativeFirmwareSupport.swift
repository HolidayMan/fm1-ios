import Foundation

/// Catalogue labels use the linked native registry, never a filename guess.
enum NativeFirmwareSupport {
    static func name(forSHA256 digest:String)->String? {
        let bytes=Array(digest.utf8)
        let kind=bytes.withUnsafeBufferPointer {instrument_native_kind_for_sha256($0.baseAddress,$0.count)}
        return name(forKind:kind)
    }
    static func name(forKind kind:UInt32)->String? {
        switch kind {
        case 2:return "SLOOP"
        case 3:return "Felucca"
        case 4:return "X0X"
        case 5:return "Melodee · INIT bank"
        case 6:return "FM1 Open · Official Preview"
        case 7:return "Skiff"
        case 8:return "FoMni"
        case 9:return "Jangada"
        case 11:return "CoralFlower"
        case 12:return "AMB-1"
        case 13:return "GHOULBOX"
        case 14:return "LOOM-8"
        case 15:return "Hortator"
        case 16:return "JIANT FM"
        case 17:return "ChoralRoot · INIT banks"
        default:return nil
        }
    }
}

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
        default:return nil
        }
    }
}

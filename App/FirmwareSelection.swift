import Foundation

/// Selection only: restoring a choice never starts audio or downloads a package.
enum FirmwareSelection {
    static let preferenceKey = "lastFirmwareID"
    static func preferred(in library: [Firmware], lastID: String?) -> Firmware? {
        if let lastID, let last = library.first(where: {$0.id == lastID}) {return last}
        // Imports append a digest to the release name; match the entire name,
        // avoiding SLOOP Floyd FM / DX7 Banks and unrelated similarly named files.
        if let current = library.first(where: {$0.name.caseInsensitiveCompare("SLOOP-2.8") == .orderedSame}) {return current}
        return library.filter {
            let name = $0.name.lowercased()
            return name == "sloop" || name.hasPrefix("sloop-") && name.dropFirst(6).first?.isNumber == true
        }.sorted {$0.name.localizedStandardCompare($1.name) == .orderedDescending}.first
    }
}

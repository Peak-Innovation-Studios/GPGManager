import Foundation

struct GPGConfig: Equatable {
    var defaultKey: String?
    var keyserver: String?
    var autoKeyRetrieve: Bool
    var preservedKeyserverOptions: [String]
    var extraLines: [String]

    static let empty = GPGConfig(
        defaultKey: nil,
        keyserver: nil,
        autoKeyRetrieve: false,
        preservedKeyserverOptions: [],
        extraLines: []
    )
}

enum GPGKeyserverPreset: String, CaseIterable, Identifiable {
    case openPGP = "hkps://keys.openpgp.org"
    case ubuntu = "hkps://keyserver.ubuntu.com"
    case mit = "hkps://pgp.mit.edu"

    var id: String { rawValue }

    var displayName: String { rawValue }
}

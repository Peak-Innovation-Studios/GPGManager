import Foundation

struct GPGInstallation: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case macGPG2 = "MacGPG2"
        case homebrew = "Homebrew"
        case path = "PATH"
        case custom = "Custom"
    }

    let id: String
    let path: String
    let kind: Kind
    var version: String?

    init(path: String, kind: Kind, version: String? = nil) {
        self.id = path
        self.path = path
        self.kind = kind
        self.version = version
    }
}

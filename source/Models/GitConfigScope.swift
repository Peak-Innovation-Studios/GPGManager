import Foundation

enum GitConfigScope: Hashable {
    case global
    case repository(path: String)

    var displayName: String {
        switch self {
        case .global:
            "Global (~/.gitconfig)"
        case .repository(let path):
            (path as NSString).lastPathComponent
        }
    }

    var detail: String? {
        switch self {
        case .global:
            "Applies to every Git repository on this Mac unless overridden."
        case .repository(let path):
            path
        }
    }

    var repositoryPath: String? {
        if case .repository(let path) = self { return path }
        return nil
    }
}

struct RememberedRepo: Codable, Hashable, Identifiable {
    var path: String
    var name: String?

    var id: String { path }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return (path as NSString).lastPathComponent
    }
}

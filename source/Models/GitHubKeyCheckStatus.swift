import Foundation

enum GitHubKeyCheckStatus: Equatable {
    case notChecked
    case checking
    case unavailable(reason: String)
    case scopeRequired(command: String)
    case loaded(registeredKeys: [GitHubRegisteredKey])

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    var registeredKeys: [GitHubRegisteredKey] {
        if case .loaded(let keys) = self { return keys }
        return []
    }

    func contains(_ keyID: String) -> Bool {
        registeredKeys.contains { $0.matches(keyID: keyID) }
    }
}

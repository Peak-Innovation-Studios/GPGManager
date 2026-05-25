import Foundation

struct PinentryInstallStatus: Equatable {
    enum State: Equatable {
        case helperMissing
        case notInstalled(currentProgram: String?)
        case installed(helperPath: String)
        case installedElsewhere(installedPath: String, expectedPath: String)
    }

    var state: State
    var previousProgram: String?

    static let helperMissing = PinentryInstallStatus(state: .helperMissing)

    var isInstalled: Bool {
        if case .installed = state { return true }
        if case .installedElsewhere = state { return true }
        return false
    }

    var needsRewrite: Bool {
        if case .installedElsewhere = state { return true }
        return false
    }
}

import Foundation

struct PinentryInstallerService {
    private static let helperName = "PinentryGPGManager"
    private static let previousProgramKey = "PreviousPinentryProgram"

    private let agentConfigStore: GPGAgentConfigStore
    private let agentService: GPGAgentService
    private let defaults: UserDefaults

    init(
        agentConfigStore: GPGAgentConfigStore = GPGAgentConfigStore(),
        agentService: GPGAgentService = GPGAgentService(),
        defaults: UserDefaults = .standard
    ) {
        self.agentConfigStore = agentConfigStore
        self.agentService = agentService
        self.defaults = defaults
    }

    var helperURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: Self.helperName)
    }

    func currentStatus() throws -> PinentryInstallStatus {
        let previous = defaults.string(forKey: Self.previousProgramKey)

        guard let helperPath = helperURL?.path else {
            return PinentryInstallStatus(state: .helperMissing, previousProgram: previous)
        }

        let config = try agentConfigStore.load()
        let current = config.pinentryProgram

        switch current {
        case nil, .some(""):
            return PinentryInstallStatus(state: .notInstalled(currentProgram: current), previousProgram: previous)
        case .some(let installed):
            if installed == helperPath {
                return PinentryInstallStatus(state: .installed(helperPath: helperPath), previousProgram: previous)
            }
            if installed.hasSuffix("/\(Self.helperName)") {
                return PinentryInstallStatus(
                    state: .installedElsewhere(installedPath: installed, expectedPath: helperPath),
                    previousProgram: previous
                )
            }
            return PinentryInstallStatus(state: .notInstalled(currentProgram: installed), previousProgram: previous)
        }
    }

    @discardableResult
    func install(gpgPath: String?) async throws -> PinentryInstallStatus {
        guard let helperPath = helperURL?.path else {
            throw PinentryInstallerError.helperNotFound
        }

        var config = try agentConfigStore.load()
        let existing = config.pinentryProgram

        if let existing,
           !existing.isEmpty,
           !existing.hasSuffix("/\(Self.helperName)") {
            defaults.set(existing, forKey: Self.previousProgramKey)
        }

        config.pinentryProgram = helperPath
        try agentConfigStore.save(config)

        try? await restartAgentIfPossible(gpgPath: gpgPath)
        return try currentStatus()
    }

    @discardableResult
    func uninstall(gpgPath: String?) async throws -> PinentryInstallStatus {
        var config = try agentConfigStore.load()
        let previous = defaults.string(forKey: Self.previousProgramKey)

        if let previous, !previous.isEmpty {
            config.pinentryProgram = previous
        } else {
            config.pinentryProgram = nil
        }

        try agentConfigStore.save(config)
        defaults.removeObject(forKey: Self.previousProgramKey)

        try? await restartAgentIfPossible(gpgPath: gpgPath)
        return try currentStatus()
    }

    private func restartAgentIfPossible(gpgPath: String?) async throws {
        guard let gpgPath, !gpgPath.isEmpty else { return }
        try await agentService.restart(gpgPath: gpgPath)
    }
}

enum PinentryInstallerError: LocalizedError {
    case helperNotFound

    var errorDescription: String? {
        switch self {
        case .helperNotFound:
            "Couldn't find the bundled PinentryGPGManager helper inside the app."
        }
    }
}

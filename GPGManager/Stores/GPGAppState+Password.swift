import Foundation

@MainActor
extension GPGAppState {
    enum PassphraseProvider: String, CaseIterable, Identifiable {
        case systemDefault
        case pinentryMac
        case gpgManager
        case custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .systemDefault: "System default"
            case .pinentryMac:   "pinentry-mac"
            case .gpgManager:    "GPG Manager (bundled)"
            case .custom:        "Custom"
            }
        }

        var description: String {
            switch self {
            case .systemDefault:
                "GPG falls back to whichever pinentry is found on PATH. Usually terminal-only — GUI apps that need a passphrase will fail."
            case .pinentryMac:
                "Native macOS dialog with built-in 'Save in Keychain' support. Requires pinentry-mac (install via Homebrew)."
            case .gpgManager:
                "The GPG Manager dialog, used by every GPG operation system-wide."
            case .custom:
                "A pinentry program you configured manually."
            }
        }
    }

    var passphraseProvider: PassphraseProvider {
        let program = agentConfig.pinentryProgram ?? ""
        if program.isEmpty { return .systemDefault }
        if program.contains("pinentry-mac") { return .pinentryMac }
        if program.hasSuffix("/PinentryGPGManager") { return .gpgManager }
        return .custom
    }

    var rememberPasswordEnabled: Bool {
        get { (agentConfig.defaultCacheTTL ?? 0) > 0 }
        set {
            if newValue {
                if agentConfig.defaultCacheTTL == nil || agentConfig.defaultCacheTTL == 0 {
                    agentConfig.defaultCacheTTL = 600
                }
                if agentConfig.maxCacheTTL == nil || agentConfig.maxCacheTTL == 0 {
                    agentConfig.maxCacheTTL = max(7200, agentConfig.defaultCacheTTL ?? 0)
                }
            } else {
                agentConfig.defaultCacheTTL = 0
                agentConfig.maxCacheTTL = 0
            }
        }
    }

    static let pinentryMacCandidates: [String] = [
        "/opt/homebrew/bin/pinentry-mac",
        "/usr/local/bin/pinentry-mac",
        "/usr/local/MacGPG2/libexec/pinentry-mac.app/Contents/MacOS/pinentry-mac"
    ]

    static func discoverPinentryMacPath() -> String? {
        pinentryMacCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isPinentryMacAvailable: Bool {
        Self.discoverPinentryMacPath() != nil
    }

    func setPassphraseProvider(_ provider: PassphraseProvider) async {
        let current = passphraseProvider
        guard current != provider else { return }

        if current == .gpgManager {
            await uninstallPinentry()
        }

        switch provider {
        case .systemDefault:
            agentConfig.pinentryProgram = nil
            saveAgentConfig()

        case .pinentryMac:
            guard let path = Self.discoverPinentryMacPath() else {
                errorMessage = "pinentry-mac isn't installed. Install via Homebrew (`brew install pinentry-mac`)."
                return
            }
            agentConfig.pinentryProgram = path
            saveAgentConfig()

        case .gpgManager:
            await installPinentry()

        case .custom:
            return
        }
    }
}

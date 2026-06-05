import AppKit
import Foundation
import Observation
import OSLog

/// Shared logger for the app-state layer. Internal (not `private`) so the
/// feature-specific `GPGAppState+…` extensions in sibling files can log too.
let appStateLog = Logger(
    subsystem: "com.peakinnovationstudios.GPGManager",
    category: "state"
)

@MainActor
@Observable
final class GPGAppState {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case signing = "Signing"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .overview: "gauge"
            case .signing: "signature"
            }
        }
    }

    var selectedSection: Section = .overview
    var installations: [GPGInstallation] = []
    var selectedGPGPath: String = UserDefaults.standard.string(forKey: "selectedGPGPath") ?? ""
    var keys: [GPGKey] = []
    var selectedKeyID: GPGKey.ID?
    var agentConfig: GPGAgentConfig = .empty
    var gpgConfig: GPGConfig = .empty
    var gitGPGProgram = ""
    var gitSigning: GitSigningConfiguration = .empty
    var gitConfigScope: GitConfigScope = .global
    var rememberedRepos: [RememberedRepo] = []
    var gitHubKeyCheck: GitHubKeyCheckStatus = .notChecked
    var gitHubUsername: String?
    /// Accounts that `gh` currently has authentication for (one entry per `gh auth login`).
    var availableGitHubAccounts: [String] = []
    /// nil means "use whichever account gh considers active".
    var selectedGitHubAccount: String?
    var pinentryStatus: PinentryInstallStatus = .helperMissing
    var statusMessage = "Ready"
    var errorMessage: String?
    var isRefreshing = false

    /// Bumped on every Keychain mutation so SwiftUI views that call
    /// hasKeychainEntry(for:) re-evaluate. exists() is a function call against
    /// the live Keychain, not a stored property, so it isn't observed
    /// automatically — touching this counter from any view that reads
    /// hasKeychainEntry forces a re-render when the Keychain changes.
    var keychainRevision: Int = 0

    // Services and persistence keys are `internal` (not `private`) so the
    // feature-specific `GPGAppState+…` extensions in sibling files can use them.
    static let selectedPathKey = "selectedGPGPath"

    let discoveryService = GPGDiscoveryService()
    let keyService = GPGKeyService()
    let agentConfigStore = GPGAgentConfigStore()
    let gpgConfigStore = GPGConfigStore()
    let agentService = GPGAgentService()
    let gitConfigService = GitConfigService()
    let rememberedReposStore = RememberedReposStore()
    let gitHubService = GitHubGPGService()
    let pinentryInstaller = PinentryInstallerService()
    let keychainStore = KeychainPassphraseStore()

    var selectedKey: GPGKey? {
        keys.first { $0.id == selectedKeyID }
    }

    var selectedInstallation: GPGInstallation? {
        installations.first { $0.path == selectedGPGPath }
    }

    var secretKeys: [GPGKey] {
        keys.filter { $0.keyClass == .secret }
    }

    func bootstrap() async {
        await refreshInstallations()
        loadAgentConfig()
        loadGPGConfig()
        refreshPinentryStatus()
        await refreshKeys()
        await refreshGitSigningConfiguration()

        // Background check — don't block bootstrap on a network call.
        Task { await refreshGitHubRegisteredKeys() }
    }

    func refreshAll() async {
        await refreshInstallations()
        loadAgentConfig()
        loadGPGConfig()
        refreshPinentryStatus()
        await refreshKeys()
        await refreshGitSigningConfiguration()
    }
}

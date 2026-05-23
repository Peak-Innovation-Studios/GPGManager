import AppKit
import Foundation
import Observation

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
    var pinentryStatus: PinentryInstallStatus = .helperMissing
    var statusMessage = "Ready"
    var errorMessage: String?
    var isRefreshing = false

    private static let selectedPathKey = "selectedGPGPath"

    private let discoveryService = GPGDiscoveryService()
    let keyService = GPGKeyService()
    private let agentConfigStore = GPGAgentConfigStore()
    private let gpgConfigStore = GPGConfigStore()
    private let agentService = GPGAgentService()
    let gitConfigService = GitConfigService()
    let rememberedReposStore = RememberedReposStore()
    let gitHubService = GitHubGPGService()
    let pinentryInstaller = PinentryInstallerService()
    private let keychainStore = KeychainPassphraseStore()

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



    func refreshInstallations() async {
        installations = await discoveryService.discover()
        if selectedGPGPath.isEmpty || !FileManager.default.isExecutableFile(atPath: selectedGPGPath) {
            selectedGPGPath = installations.first?.path ?? ""
            persistSelectedPath()
        }
    }

    func selectGPGPath(_ path: String) async {
        selectedGPGPath = path
        persistSelectedPath()
        await refreshKeys()
    }

    func chooseCustomGPGPath() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a GPG executable."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let installation = GPGInstallation(path: url.path, kind: .custom)
        if !installations.contains(where: { $0.path == installation.path }) {
            installations.append(installation)
        }
        await selectGPGPath(url.path)
    }

    func refreshKeys() async {
        guard !selectedGPGPath.isEmpty else {
            keys = []
            statusMessage = "No GPG executable selected."
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            keys = try await keyService.listKeys(gpgPath: selectedGPGPath)
            if selectedKeyID == nil {
                selectedKeyID = keys.first?.id
            }
            statusMessage = "Loaded \(keys.count) keys."
            errorMessage = nil
        } catch {
            keys = []
            errorMessage = error.localizedDescription
            statusMessage = "Could not load keys."
        }
    }

    func createKey(parameters: GPGCreateKeyParameters, saveToKeychain: Bool = false, uploadToGitHub: Bool = false) async throws {
        guard !selectedGPGPath.isEmpty else {
            throw GPGServiceError.commandFailed("No GPG executable selected.")
        }
        let result = try await keyService.createKey(gpgPath: selectedGPGPath, parameters: parameters)

        if saveToKeychain, let fingerprint = result.fingerprint {
            if let keygrip = try? await keyService.fetchPrimaryKeygrip(gpgPath: selectedGPGPath, fingerprint: fingerprint) {
                _ = keychainStore.savePassphrase(parameters.passphrase, account: keygrip)
            }
        }

        statusMessage = "Created new key for \(parameters.email)."
        errorMessage = nil
        await refreshKeys()

        if uploadToGitHub,
           let fingerprint = result.fingerprint,
           let key = secretKeys.first(where: { $0.fingerprint == fingerprint }) {
            await uploadKeyToGitHub(key, name: parameters.name)
        }
    }

    func importKey(from url: URL) async {
        guard !selectedGPGPath.isEmpty else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let output = try await keyService.importKey(gpgPath: selectedGPGPath, fileURL: url)
            statusMessage = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Imported key." : output
            errorMessage = nil
            await refreshKeys()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyPublicKeyToPasteboard(_ key: GPGKey) async {
        do {
            let exported = try await keyService.exportPublicKey(gpgPath: selectedGPGPath, fingerprint: key.fingerprint)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(exported, forType: .string)
            statusMessage = "Copied public key for \(key.shortFingerprint)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAgentConfig() {
        do {
            agentConfig = try agentConfigStore.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAgentConfig() {
        do {
            try agentConfigStore.save(agentConfig)
            statusMessage = "Saved \(agentConfigStore.configURL.path)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadGPGConfig() {
        do {
            gpgConfig = try gpgConfigStore.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveGPGConfig() {
        do {
            try gpgConfigStore.save(gpgConfig)
            statusMessage = "Saved \(gpgConfigStore.configURL.path)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setDefaultKey(_ key: GPGKey) {
        gpgConfig.defaultKey = key.keyID
        saveGPGConfig()
        statusMessage = "Default key set to \(key.primaryUserID)."
    }

    func restartAgent() async {
        guard !selectedGPGPath.isEmpty else { return }

        do {
            try await agentService.restart(gpgPath: selectedGPGPath)
            statusMessage = "Restarted gpg-agent."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistSelectedPath() {
        UserDefaults.standard.set(selectedGPGPath, forKey: Self.selectedPathKey)
    }
}

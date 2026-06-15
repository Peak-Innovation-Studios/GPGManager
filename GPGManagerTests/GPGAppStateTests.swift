import Foundation
import Testing
@testable import GPGManager

/// Non-isolated fixtures: referenced from `@Sendable` runner closures, so they
/// must not be `@MainActor`-isolated (which a member of the test struct is).
private enum Fixture {
    static let gpg = "/usr/bin/gpg"
    static let fingerprint = "0123456789ABCDEF0123456789ABCDEF01234567"
    static let keygrip = "1111111111111111111111111111111111111111"

    static let publicListing = """
    pub:u:4096:1:ABCDEF1234567890:1700000000:1800000000::u:::scESC::::::23::0:
    fpr:::::::::\(fingerprint):
    uid:u::::1700000000::hash::Dev Peak <dev@example.com>::::::::::0:
    """

    static let secretListing = """
    sec:u:4096:1:ABCDEF1234567890:1700000000::::::::::
    fpr:::::::::\(fingerprint):
    """

    static let keygripListing = secretListing + "\ngrp:::::::::\(keygrip):"
}

@MainActor
struct GPGAppStateTests {
    // MARK: - refreshKeys

    @Test
    func refreshKeysPopulatesKeysAndStatus() async {
        let fake = FakeCommandRunner { inv in
            inv.arguments.contains("--list-secret-keys")
                ? .ok(stdout: Fixture.secretListing)
                : .ok(stdout: Fixture.publicListing)
        }
        let state = GPGAppState(keyService: GPGKeyService(runner: fake))
        state.selectedGPGPath = Fixture.gpg

        await state.refreshKeys()

        #expect(state.keys.count == 1)
        #expect(state.errorMessage == nil)
        #expect(state.statusMessage == "Loaded 1 keys.")
    }

    @Test
    func refreshKeysWithoutSelectedPathClearsKeys() async {
        let state = GPGAppState(keyService: GPGKeyService(runner: FakeCommandRunner(result: .ok())))
        state.selectedGPGPath = ""
        state.keys = []

        await state.refreshKeys()

        #expect(state.keys.isEmpty)
        #expect(state.statusMessage == "No GPG executable selected.")
    }

    @Test
    func refreshKeysSetsErrorWhenListingFails() async {
        let fake = FakeCommandRunner(result: .failure(stderr: "keyboxd down"))
        let state = GPGAppState(keyService: GPGKeyService(runner: fake))
        state.selectedGPGPath = Fixture.gpg

        await state.refreshKeys()

        #expect(state.keys.isEmpty)
        #expect(state.errorMessage != nil)
        #expect(state.statusMessage == "Could not load keys.")
    }

    // MARK: - createKey

    @Test
    func createKeySavesPassphraseToKeychainWhenRequested() async throws {
        let log = "gpg: revocation certificate stored as '/x/openpgp-revocs.d/\(Fixture.fingerprint).rev'"
        let fake = FakeCommandRunner { inv in
            let args = inv.arguments
            if args.contains("--gen-key") { return .ok(stderr: log) }
            if args.contains("--list-secret-keys") {
                return args.contains(Fixture.fingerprint)
                    ? .ok(stdout: Fixture.keygripListing)
                    : .ok(stdout: Fixture.secretListing)
            }
            return .ok(stdout: Fixture.publicListing)
        }
        let keychain = FakeKeychainStore()
        let state = GPGAppState(keyService: GPGKeyService(runner: fake), keychainStore: keychain)
        state.selectedGPGPath = Fixture.gpg

        var params = GPGCreateKeyParameters()
        params.name = "Dev Peak"
        params.email = "dev@example.com"
        params.passphrase = "pw"

        try await state.createKey(parameters: params, saveToKeychain: true)

        #expect(keychain.savedAccounts == [Fixture.keygrip])
        #expect(state.keychainRevision == 1)
        #expect(state.errorMessage == nil)
    }

    @Test
    func createKeyWithoutKeychainTouchesNoKeychain() async throws {
        let log = "gpg: revocation certificate stored as '/x/openpgp-revocs.d/\(Fixture.fingerprint).rev'"
        let fake = FakeCommandRunner { inv in
            let args = inv.arguments
            if args.contains("--gen-key") { return .ok(stderr: log) }
            if args.contains("--list-secret-keys") { return .ok(stdout: Fixture.secretListing) }
            return .ok(stdout: Fixture.publicListing)
        }
        let keychain = FakeKeychainStore()
        let state = GPGAppState(keyService: GPGKeyService(runner: fake), keychainStore: keychain)
        state.selectedGPGPath = Fixture.gpg

        var params = GPGCreateKeyParameters()
        params.name = "Dev Peak"
        params.email = "dev@example.com"
        params.passphrase = "pw"

        try await state.createKey(parameters: params, saveToKeychain: false)

        #expect(keychain.savedAccounts.isEmpty)
        #expect(state.errorMessage == nil)
    }

    // MARK: - deleteKey

    @Test
    func deleteKeyRemovesKeychainEntriesForEachKeygrip() async {
        let fake = FakeCommandRunner { inv in
            let args = inv.arguments
            if args.contains("--delete-secret-keys") || args.contains("--delete-keys") { return .ok() }
            if args.contains("--list-secret-keys") && args.contains(Fixture.fingerprint) {
                return .ok(stdout: Fixture.keygripListing)
            }
            return .ok()
        }
        let keychain = FakeKeychainStore()
        keychain.existingAccounts = [Fixture.keygrip]
        let state = GPGAppState(keyService: GPGKeyService(runner: fake), keychainStore: keychain)
        state.selectedGPGPath = Fixture.gpg

        let key = GPGKey(
            id: Fixture.fingerprint,
            keyClass: .secret,
            keyID: "ABCDEF1234567890",
            fingerprint: Fixture.fingerprint,
            userIDs: ["Dev Peak <dev@example.com>"],
            createdAt: nil,
            expiresAt: nil,
            capabilities: "scESC",
            trust: "u",
            algorithmCode: 1,
            bitLength: 4096
        )

        await state.deleteKey(key)

        #expect(keychain.deletedAccounts == [Fixture.keygrip])
        #expect(state.errorMessage == nil)
    }

    // MARK: - Git signing

    @Test
    func applyGitSigningConfigurationReportsSuccess() async {
        let fake = FakeCommandRunner(result: .ok())
        let state = GPGAppState(gitConfigService: GitConfigService(runner: fake))
        state.selectedGPGPath = Fixture.gpg

        var config = GitSigningConfiguration.empty
        config.signsCommits = true
        await state.applyGitSigningConfiguration(config)

        #expect(state.errorMessage == nil)
        #expect(state.statusMessage.contains("Git signing"))
    }

    // MARK: - GitHub

    @Test
    func refreshGitHubRegisteredKeysLoadsAccountsAndKeys() async {
        let fake = FakeCommandRunner { inv in
            let args = inv.arguments
            if args.contains("status") {
                return .ok(stdout: "✓ Logged in to github.com account octocat (keyring)")
            }
            if args == ["api", "user", "--jq", ".login"] { return .ok(stdout: "octocat") }
            if args.contains("user/gpg_keys") { return .ok(stdout: "[]") }
            return .ok()
        }
        let state = GPGAppState(gitHubService: GitHubGPGService(runner: fake, fileIsExecutable: { _ in true }))

        await state.refreshGitHubRegisteredKeys()

        #expect(state.availableGitHubAccounts == ["octocat"])
        if case .loaded(let keys) = state.gitHubKeyCheck {
            #expect(keys.isEmpty)
        } else {
            Issue.record("Expected .loaded, got \(state.gitHubKeyCheck)")
        }
    }
}

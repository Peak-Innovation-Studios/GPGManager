import Foundation
@testable import GPGManager

/// Stub `CommandRunning` that records every invocation and returns canned
/// results, so IO-service tests can assert on the command line built and feed
/// back stdout / exit codes without launching a real process.
final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    struct Invocation {
        let executablePath: String
        let arguments: [String]
        let standardInput: String?
        let environment: [String: String]
    }

    private let lock = NSLock()
    private var storedInvocations: [Invocation] = []
    private let handler: @Sendable (Invocation) throws -> CommandResult

    init(handler: @escaping @Sendable (Invocation) throws -> CommandResult) {
        self.handler = handler
    }

    /// Always returns the same result, regardless of the command.
    convenience init(result: CommandResult) {
        self.init(handler: { _ in result })
    }

    var invocations: [Invocation] {
        lock.lock(); defer { lock.unlock() }
        return storedInvocations
    }

    func run(
        executablePath: String,
        arguments: [String],
        standardInput: String?,
        environment: [String: String]
    ) async throws -> CommandResult {
        let invocation = Invocation(
            executablePath: executablePath,
            arguments: arguments,
            standardInput: standardInput,
            environment: environment
        )
        lock.lock()
        storedInvocations.append(invocation)
        lock.unlock()
        return try handler(invocation)
    }
}

extension CommandResult {
    static func ok(stdout: String = "", stderr: String = "") -> CommandResult {
        CommandResult(exitCode: 0, stdout: stdout, stderr: stderr)
    }

    static func failure(exitCode: Int32 = 1, stdout: String = "", stderr: String = "") -> CommandResult {
        CommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }
}

/// In-memory `KeychainPassphraseStoring` so `GPGAppState` orchestration tests
/// can exercise the keychain branches without the real Keychain.
final class FakeKeychainStore: KeychainPassphraseStoring, @unchecked Sendable {
    var existingAccounts: Set<String> = []
    var saveSucceeds = true
    var migrationResult: KeychainPassphraseStore.MigrationResult = .migrated
    private(set) var savedAccounts: [String] = []
    private(set) var deletedAccounts: [String] = []
    private(set) var migratedAccounts: [String] = []

    func exists(account: String) -> Bool { existingAccounts.contains(account) }

    @discardableResult
    func savePassphrase(_ passphrase: String, account: String, label: String?) -> Bool {
        savedAccounts.append(account)
        if saveSucceeds { existingAccounts.insert(account) }
        return saveSucceeds
    }

    func deletePassphrase(account: String) {
        deletedAccounts.append(account)
        existingAccounts.remove(account)
    }

    func migrateToBiometric(account: String) -> KeychainPassphraseStore.MigrationResult {
        migratedAccounts.append(account)
        return migrationResult
    }
}

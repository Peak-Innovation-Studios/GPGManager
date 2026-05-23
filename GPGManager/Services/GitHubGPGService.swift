import Foundation

/// Shells out to the `gh` CLI to read and modify the user's registered GPG keys
/// on GitHub. Requires `gh` installed and `gh auth login` completed with the
/// `admin:gpg_key` scope for write operations.
struct GitHubGPGService {
    enum FetchError: LocalizedError {
        case ghMissing
        case ghFailed(String)
        case scopeRequired(command: String)

        var errorDescription: String? {
            switch self {
            case .ghMissing:
                "Install the gh CLI (brew install gh) and run `gh auth login` to enable GitHub checks."
            case .ghFailed(let message):
                message.isEmpty ? "Couldn't talk to GitHub via gh." : message
            case .scopeRequired(let command):
                "Run this in Terminal to grant GitHub access: \(command)"
            }
        }
    }

    static let recommendedScopeCommand = "gh auth refresh -h github.com -s admin:gpg_key"

    private let runner = GPGCommandRunner()
    private let ghCandidates: [String] = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh"
    ]

    /// Returns the `login` of the currently authenticated GitHub user, or nil
    /// if gh is not signed in. Used to caption which account the keys belong to.
    func fetchAuthenticatedUser() async throws -> String? {
        let ghPath = try resolveGhPath()
        let result = try await runner.run(
            executablePath: ghPath,
            arguments: ["api", "user", "--jq", ".login"]
        )
        guard result.succeeded else { return nil }
        let login = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? nil : login
    }

    /// Returns the user's full list of registered GPG keys with metadata.
    func fetchRegisteredKeys() async throws -> [GitHubRegisteredKey] {
        let ghPath = try resolveGhPath()
        let result: CommandResult
        do {
            result = try await runner.run(executablePath: ghPath, arguments: ["api", "user/gpg_keys"])
        } catch {
            throw FetchError.ghFailed(error.localizedDescription)
        }
        try ensureSuccess(result)

        guard let data = result.stdout.data(using: .utf8) else {
            throw FetchError.ghFailed("gh returned non-UTF8 output.")
        }

        let payload: [APIKey]
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode([APIKey].self, from: data)
        } catch {
            throw FetchError.ghFailed("Couldn't parse gh JSON: \(error.localizedDescription)")
        }

        return payload.map { $0.toModel() }
    }

    /// Removes a registered key by its GitHub internal ID. Requires `admin:gpg_key`.
    func deleteKey(githubID: Int) async throws {
        let ghPath = try resolveGhPath()
        let result: CommandResult
        do {
            result = try await runner.run(
                executablePath: ghPath,
                arguments: ["api", "-X", "DELETE", "user/gpg_keys/\(githubID)"]
            )
        } catch {
            throw FetchError.ghFailed(error.localizedDescription)
        }
        try ensureSuccess(result)
    }

    /// Uploads an armored public key with an optional display name.
    /// Uses `gh api --input -` with a JSON body so the `name` parameter can be passed.
    /// The caller should refresh the registered-keys list to pick up the new entry.
    func uploadKey(armoredPublic: String, name: String? = nil) async throws {
        let ghPath = try resolveGhPath()

        var body: [String: Any] = ["armored_public_key": armoredPublic]
        if let name, !name.isEmpty { body["name"] = name }

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw FetchError.ghFailed("Couldn't serialize upload payload: \(error.localizedDescription)")
        }
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw FetchError.ghFailed("Couldn't encode upload payload as UTF-8.")
        }

        let result: CommandResult
        do {
            result = try await runner.run(
                executablePath: ghPath,
                arguments: ["api", "-X", "POST", "--input", "-", "user/gpg_keys"],
                standardInput: jsonString
            )
        } catch {
            throw FetchError.ghFailed(error.localizedDescription)
        }
        try ensureSuccess(result)
    }

    private func resolveGhPath() throws -> String {
        guard let path = ghCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw FetchError.ghMissing
        }
        return path
    }

    private func ensureSuccess(_ result: CommandResult) throws {
        guard !result.succeeded else { return }
        let message = (result.stderr.isEmpty ? result.stdout : result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if message.localizedCaseInsensitiveContains("admin:gpg_key")
            || message.localizedCaseInsensitiveContains("read:gpg_key") {
            throw FetchError.scopeRequired(command: Self.recommendedScopeCommand)
        }
        throw FetchError.ghFailed(message)
    }

    private struct APIKey: Decodable {
        let id: Int
        let key_id: String
        let name: String?
        let emails: [APIEmail]?
        let created_at: Date?
        let expires_at: Date?
        let subkeys: [APISubkey]?

        func toModel() -> GitHubRegisteredKey {
            GitHubRegisteredKey(
                id: id,
                keyID: key_id,
                name: name,
                emails: emails?.map(\.email) ?? [],
                createdAt: created_at,
                expiresAt: expires_at,
                subkeyIDs: subkeys?.map(\.key_id) ?? []
            )
        }
    }

    private struct APIEmail: Decodable {
        let email: String
    }

    private struct APISubkey: Decodable {
        let key_id: String
    }
}

import Foundation

/// Shells out to the `gh` CLI to read and modify the user's registered GPG keys
/// on GitHub. Supports multiple authenticated accounts: when `account` is
/// supplied, the call is routed through that account's token via the
/// `GH_TOKEN` environment variable, leaving the user's terminal `gh` context
/// untouched.
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

    /// Returns the list of GitHub accounts currently authenticated through `gh`.
    /// Parses `gh auth status --hostname github.com` text output since gh
    /// doesn't expose a structured form for it.
    func fetchAccounts() async throws -> [String] {
        let ghPath = try resolveGhPath()
        let result = try await runner.run(
            executablePath: ghPath,
            arguments: ["auth", "status", "--hostname", "github.com"]
        )
        // gh exits 0 when at least one account is logged in; non-zero means no auth.
        guard result.succeeded else { return [] }
        let combined = result.stdout + "\n" + result.stderr
        return GitHubGPGService.parseAccounts(from: combined)
    }

    static func parseAccounts(from text: String) -> [String] {
        var logins: Set<String> = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // Pattern: "Logged in to github.com account <login> (...)"
            guard let range = line.range(of: "account ") else { continue }
            let tail = line[range.upperBound...]
            let token = tail.split(whereSeparator: { $0.isWhitespace || $0 == "(" }).first
            if let token, !token.isEmpty {
                logins.insert(String(token))
            }
        }
        return logins.sorted()
    }

    /// Returns the `login` of the (selected, or gh's active) GitHub user.
    func fetchAuthenticatedUser(forAccount account: String? = nil) async throws -> String? {
        let ghPath = try resolveGhPath()
        let env = try await environment(for: account)
        let result = try await runner.run(
            executablePath: ghPath,
            arguments: ["api", "user", "--jq", ".login"],
            environment: env
        )
        guard result.succeeded else { return nil }
        let login = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? nil : login
    }

    func fetchRegisteredKeys(forAccount account: String? = nil) async throws -> [GitHubRegisteredKey] {
        let ghPath = try resolveGhPath()
        let env = try await environment(for: account)
        let result: CommandResult
        do {
            result = try await runner.run(
                executablePath: ghPath,
                arguments: ["api", "user/gpg_keys"],
                environment: env
            )
        } catch {
            throw FetchError.ghFailed(error.localizedDescription)
        }
        try ensureSuccess(result)

        guard let data = result.stdout.data(using: .utf8) else {
            throw FetchError.ghFailed("gh returned non-UTF8 output.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([APIKey].self, from: data).map { $0.toModel() }
        } catch {
            throw FetchError.ghFailed("Couldn't parse gh JSON: \(error.localizedDescription)")
        }
    }

    func deleteKey(githubID: Int, forAccount account: String? = nil) async throws {
        let ghPath = try resolveGhPath()
        let env = try await environment(for: account)
        let result: CommandResult
        do {
            result = try await runner.run(
                executablePath: ghPath,
                arguments: ["api", "-X", "DELETE", "user/gpg_keys/\(githubID)"],
                environment: env
            )
        } catch {
            throw FetchError.ghFailed(error.localizedDescription)
        }
        try ensureSuccess(result)
    }

    func uploadKey(armoredPublic: String, name: String? = nil, forAccount account: String? = nil) async throws {
        let ghPath = try resolveGhPath()
        let env = try await environment(for: account)

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
                standardInput: jsonString,
                environment: env
            )
        } catch {
            throw FetchError.ghFailed(error.localizedDescription)
        }
        try ensureSuccess(result)
    }

    /// Builds an env dict suitable for routing through a specific account.
    /// When `account` is nil we leave `GH_TOKEN` unset and gh uses whichever
    /// account it considers active.
    private func environment(for account: String?) async throws -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Strip any inherited GH_TOKEN so gh's stored auth wins when no account is selected.
        env["GH_TOKEN"] = nil
        guard let account, !account.isEmpty else { return env }

        let ghPath = try resolveGhPath()
        let tokenResult = try await runner.run(
            executablePath: ghPath,
            arguments: ["auth", "token", "--user", account, "--hostname", "github.com"]
        )
        guard tokenResult.succeeded else {
            throw FetchError.ghFailed(
                "Couldn't resolve token for \(account). Try `gh auth login -u \(account)`."
            )
        }
        let token = tokenResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty { env["GH_TOKEN"] = token }
        return env
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

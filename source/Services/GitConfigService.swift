import Foundation

struct GitConfigService {
    private let runner: any CommandRunning
    private let gitPath = "/usr/bin/git"

    init(runner: any CommandRunning = GPGCommandRunner()) {
        self.runner = runner
    }

    func currentConfiguration(scope: GitConfigScope = .global) async -> GitSigningConfiguration {
        switch scope {
        case .global:
            return await readGlobalConfiguration()
        case .repository(let path):
            return await readRepositoryConfiguration(path: path)
        }
    }

    func apply(_ configuration: GitSigningConfiguration, scope: GitConfigScope = .global) async throws {
        let global = await readGlobalConfiguration()

        switch scope {
        case .global:
            try await writeOrUnset("user.signingkey", value: configuration.signingKey, scope: .global)
            try await setValue("commit.gpgsign", value: boolString(configuration.signsCommits), scope: .global)
            try await setValue("tag.gpgsign", value: boolString(configuration.signsTags), scope: .global)
            try await setValue("log.showSignature", value: boolString(configuration.showsLogSignatures), scope: .global)
        case .repository:
            try await inheritOrSet("user.signingkey", value: configuration.signingKey, globalValue: global.signingKey, scope: scope)
            try await inheritOrSetBool("commit.gpgsign", value: configuration.signsCommits, globalValue: global.signsCommits, scope: scope)
            try await inheritOrSetBool("tag.gpgsign", value: configuration.signsTags, globalValue: global.signsTags, scope: scope)
            try await inheritOrSetBool("log.showSignature", value: configuration.showsLogSignatures, globalValue: global.showsLogSignatures, scope: scope)
        }

        // gpg.program always lives at the global level.
        if let gpgProgram = configuration.gpgProgram, !gpgProgram.isEmpty {
            try await setValue("gpg.program", value: gpgProgram, scope: .global)
        }
        if case .repository = scope {
            try await unsetValue("gpg.program", scope: scope)
        }
    }

    func currentGPGProgram() async -> String {
        await readValue("gpg.program", scope: .global) ?? ""
    }

    func setGPGProgram(_ path: String) async throws {
        try await setValue("gpg.program", value: path, scope: .global)
    }

    func isGitRepository(at path: String) async -> Bool {
        guard let result = try? await runner.run(
            executablePath: gitPath,
            arguments: ["-C", path, "rev-parse", "--is-inside-work-tree"]
        ) else { return false }
        return result.succeeded && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    // MARK: - Read helpers

    private func readGlobalConfiguration() async -> GitSigningConfiguration {
        async let signingKey = readValue("user.signingkey", scope: .global)
        async let gpgProgram = readValue("gpg.program", scope: .global)
        async let signsCommits = readBool("commit.gpgsign", scope: .global)
        async let signsTags = readBool("tag.gpgsign", scope: .global)
        async let showsLogSignatures = readBool("log.showSignature", scope: .global)
        async let userName = readValue("user.name", scope: .global)
        async let userEmail = readValue("user.email", scope: .global)

        return GitSigningConfiguration(
            signingKey: await signingKey,
            gpgProgram: await gpgProgram,
            signsCommits: await signsCommits,
            signsTags: await signsTags,
            showsLogSignatures: await showsLogSignatures,
            userName: await userName,
            userEmail: await userEmail,
            userOverriddenLocally: false,
            signingKeyOverriddenLocally: false,
            signsCommitsOverriddenLocally: false,
            signsTagsOverriddenLocally: false,
            showsLogSignaturesOverriddenLocally: false
        )
    }

    private func readRepositoryConfiguration(path: String) async -> GitSigningConfiguration {
        async let effectiveSigningKey = readEffective("user.signingkey", at: path)
        async let effectiveGpgProgram = readEffective("gpg.program", at: path)
        async let effectiveSignsCommits = readEffectiveBool("commit.gpgsign", at: path)
        async let effectiveSignsTags = readEffectiveBool("tag.gpgsign", at: path)
        async let effectiveShowsLogSignatures = readEffectiveBool("log.showSignature", at: path)
        async let localSigningKey = readValue("user.signingkey", scope: .repository(path: path))
        async let localSignsCommits = readValue("commit.gpgsign", scope: .repository(path: path))
        async let localSignsTags = readValue("tag.gpgsign", scope: .repository(path: path))
        async let localShowsLogSignatures = readValue("log.showSignature", scope: .repository(path: path))
        async let effectiveName = readEffective("user.name", at: path)
        async let effectiveEmail = readEffective("user.email", at: path)
        async let localName = readValue("user.name", scope: .repository(path: path))
        async let localEmail = readValue("user.email", scope: .repository(path: path))

        let resolvedLocalName = await localName
        let resolvedLocalEmail = await localEmail
        let userOverridden = resolvedLocalName != nil || resolvedLocalEmail != nil

        return GitSigningConfiguration(
            signingKey: await effectiveSigningKey,
            gpgProgram: await effectiveGpgProgram,
            signsCommits: await effectiveSignsCommits,
            signsTags: await effectiveSignsTags,
            showsLogSignatures: await effectiveShowsLogSignatures,
            userName: await effectiveName,
            userEmail: await effectiveEmail,
            userOverriddenLocally: userOverridden,
            signingKeyOverriddenLocally: await localSigningKey != nil,
            signsCommitsOverriddenLocally: await localSignsCommits != nil,
            signsTagsOverriddenLocally: await localSignsTags != nil,
            showsLogSignaturesOverriddenLocally: await localShowsLogSignatures != nil
        )
    }

    private func readValue(_ key: String, scope: GitConfigScope) async -> String? {
        guard let result = try? await runner.run(
            executablePath: gitPath,
            arguments: arguments(for: scope, action: ["config", scopeFlag(scope), "--get", key])
        ), result.succeeded else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readBool(_ key: String, scope: GitConfigScope) async -> Bool {
        guard let value = await readValue(key, scope: scope)?.lowercased() else { return false }
        return value == "true" || value == "yes" || value == "1" || value == "on"
    }

    private func readEffective(_ key: String, at repositoryPath: String) async -> String? {
        guard let result = try? await runner.run(
            executablePath: gitPath,
            arguments: ["-C", repositoryPath, "config", "--get", key]
        ), result.succeeded else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readEffectiveBool(_ key: String, at repositoryPath: String) async -> Bool {
        guard let value = await readEffective(key, at: repositoryPath)?.lowercased() else { return false }
        return value == "true" || value == "yes" || value == "1" || value == "on"
    }

    // MARK: - Write helpers

    private func writeOrUnset(_ key: String, value: String?, scope: GitConfigScope) async throws {
        if let value, !value.isEmpty {
            try await setValue(key, value: value, scope: scope)
        } else {
            try await unsetValue(key, scope: scope)
        }
    }

    private func inheritOrSet(_ key: String, value: String?, globalValue: String?, scope: GitConfigScope) async throws {
        let normalized = (value?.isEmpty == false) ? value : nil
        if normalized == globalValue {
            try await unsetValue(key, scope: scope)
        } else if let normalized {
            try await setValue(key, value: normalized, scope: scope)
        } else {
            try await unsetValue(key, scope: scope)
        }
    }

    private func inheritOrSetBool(_ key: String, value: Bool, globalValue: Bool, scope: GitConfigScope) async throws {
        if value == globalValue {
            try await unsetValue(key, scope: scope)
        } else {
            try await setValue(key, value: boolString(value), scope: scope)
        }
    }

    private func boolString(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private func setValue(_ key: String, value: String, scope: GitConfigScope) async throws {
        let result = try await runner.run(
            executablePath: gitPath,
            arguments: arguments(for: scope, action: ["config", scopeFlag(scope), key, value])
        )
        guard result.succeeded else {
            throw GPGServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    private func unsetValue(_ key: String, scope: GitConfigScope) async throws {
        let result = try await runner.run(
            executablePath: gitPath,
            arguments: arguments(for: scope, action: ["config", scopeFlag(scope), "--unset", key])
        )
        if result.exitCode == 0 || result.exitCode == 5 { return }
        throw GPGServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
    }

    private func arguments(for scope: GitConfigScope, action: [String]) -> [String] {
        switch scope {
        case .global:                return action
        case .repository(let path):  return ["-C", path] + action
        }
    }

    private func scopeFlag(_ scope: GitConfigScope) -> String {
        switch scope {
        case .global:     "--global"
        case .repository: "--local"
        }
    }
}

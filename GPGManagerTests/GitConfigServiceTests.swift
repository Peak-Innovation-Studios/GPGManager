import Testing
@testable import GPGManager

struct GitConfigServiceTests {
    @Test
    func isGitRepositoryTrueWhenInsideWorkTree() async {
        let fake = FakeCommandRunner(result: .ok(stdout: "true\n"))
        let inside = await GitConfigService(runner: fake).isGitRepository(at: "/repo")

        #expect(inside)
        #expect(fake.invocations[0].arguments == ["-C", "/repo", "rev-parse", "--is-inside-work-tree"])
    }

    @Test
    func isGitRepositoryFalseWhenNotAWorkTree() async {
        let fake = FakeCommandRunner(result: .ok(stdout: "false"))
        #expect(await GitConfigService(runner: fake).isGitRepository(at: "/x") == false)
    }

    @Test
    func isGitRepositoryFalseWhenCommandFails() async {
        let fake = FakeCommandRunner(result: .failure())
        #expect(await GitConfigService(runner: fake).isGitRepository(at: "/x") == false)
    }

    @Test
    func currentGlobalConfigurationMapsValues() async {
        let fake = FakeCommandRunner { inv in
            switch inv.arguments.last {
            case "user.signingkey": return .ok(stdout: "ABCDEF\n")
            case "commit.gpgsign":  return .ok(stdout: "true")
            case "user.email":      return .ok(stdout: "dev@example.com")
            default:                return .failure()
            }
        }
        let config = await GitConfigService(runner: fake).currentConfiguration(scope: .global)

        #expect(config.signingKey == "ABCDEF")
        #expect(config.signsCommits == true)
        #expect(config.signsTags == false)
        #expect(config.userEmail == "dev@example.com")
    }

    @Test
    func applyGlobalUnsetsSigningKeyWhenNil() async throws {
        let fake = FakeCommandRunner(result: .ok())
        let config = GitSigningConfiguration(
            signingKey: nil,
            gpgProgram: nil,
            signsCommits: false,
            signsTags: false,
            userName: nil,
            userEmail: nil
        )
        try await GitConfigService(runner: fake).apply(config, scope: .global)

        let unsetSigning = fake.invocations.contains {
            $0.arguments.contains("--unset") && $0.arguments.contains("user.signingkey")
        }
        #expect(unsetSigning)
    }

    @Test
    func applyGlobalWritesGpgProgramWhenProvided() async throws {
        let fake = FakeCommandRunner(result: .ok())
        var config = GitSigningConfiguration.empty
        config.gpgProgram = "/opt/homebrew/bin/gpg"
        try await GitConfigService(runner: fake).apply(config, scope: .global)

        let wroteProgram = fake.invocations.contains {
            $0.arguments.contains("gpg.program") && $0.arguments.contains("/opt/homebrew/bin/gpg")
        }
        #expect(wroteProgram)
    }

    @Test
    func applyGlobalWritesUserEmailWhenProvided() async throws {
        let fake = FakeCommandRunner(result: .ok())
        var config = GitSigningConfiguration.empty
        config.userEmail = "studios@example.com"
        try await GitConfigService(runner: fake).apply(config, scope: .global)

        let wroteEmail = fake.invocations.contains {
            $0.arguments.contains("--global")
                && $0.arguments.contains("user.email")
                && $0.arguments.contains("studios@example.com")
        }
        #expect(wroteEmail)
    }

    @Test
    func applyRepositorySetsLocalUserEmailWhenItDiffersFromGlobal() async throws {
        // All reads return empty (global user.email == nil), so the local email differs.
        let fake = FakeCommandRunner(result: .ok())
        var config = GitSigningConfiguration.empty
        config.signingKey = "ABCDEF"
        config.userEmail = "studios@example.com"
        try await GitConfigService(runner: fake).apply(config, scope: .repository(path: "/repo"))

        let wroteLocalEmail = fake.invocations.contains {
            $0.arguments.contains("-C") && $0.arguments.contains("/repo")
                && $0.arguments.contains("--local")
                && $0.arguments.contains("user.email")
                && $0.arguments.contains("studios@example.com")
        }
        #expect(wroteLocalEmail)
    }

    @Test
    func applyDoesNotTouchUserEmailWhenNoneProvided() async throws {
        let fake = FakeCommandRunner(result: .ok())
        let config = GitSigningConfiguration.empty // userEmail is nil
        try await GitConfigService(runner: fake).apply(config, scope: .global)

        // The only permissible user.email reference is the read (`--get`) during
        // readGlobalConfiguration. Nothing should write or unset it.
        let mutatedEmail = fake.invocations.contains {
            $0.arguments.contains("user.email") && !$0.arguments.contains("--get")
        }
        #expect(!mutatedEmail)
    }
}

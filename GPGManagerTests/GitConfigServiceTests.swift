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
}

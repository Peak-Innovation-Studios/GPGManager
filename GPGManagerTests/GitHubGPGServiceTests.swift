import Testing
@testable import GPGManager

struct GitHubGPGServiceTests {
    private func service(_ fake: FakeCommandRunner) -> GitHubGPGService {
        GitHubGPGService(runner: fake, fileIsExecutable: { _ in true })
    }

    @Test
    func fetchAccountsThrowsWhenGhMissing() async {
        let svc = GitHubGPGService(runner: FakeCommandRunner(result: .ok()), fileIsExecutable: { _ in false })
        await #expect(throws: GitHubGPGService.FetchError.self) {
            _ = try await svc.fetchAccounts()
        }
    }

    @Test
    func fetchAccountsParsesAndSortsLogins() async throws {
        let status = """
        ✓ Logged in to github.com account octocat (keyring)
        ✓ Logged in to github.com account hubber (oauth_token)
        """
        let accounts = try await service(FakeCommandRunner(result: .ok(stdout: status))).fetchAccounts()
        #expect(accounts == ["hubber", "octocat"])
    }

    @Test
    func fetchRegisteredKeysDecodesJSON() async throws {
        let json = #"[{"id":1,"key_id":"ABC123","name":"laptop","emails":[],"created_at":null,"expires_at":null,"subkeys":[]}]"#
        let keys = try await service(FakeCommandRunner(result: .ok(stdout: json))).fetchRegisteredKeys()

        #expect(keys.count == 1)
        #expect(keys[0].keyID == "ABC123")
    }

    @Test
    func fetchRegisteredKeysMapsMissingScopeToScopeRequired() async {
        let stderr = "error: your token has not been granted the required scopes to execute this query. missing: 'admin:gpg_key'"
        let svc = service(FakeCommandRunner(result: .failure(stderr: stderr)))
        await #expect(throws: GitHubGPGService.FetchError.self) {
            _ = try await svc.fetchRegisteredKeys()
        }
    }

    @Test
    func deleteKeyBuildsDeleteRequest() async throws {
        let fake = FakeCommandRunner(result: .ok())
        try await service(fake).deleteKey(githubID: 42)

        let apiCall = fake.invocations.first { $0.arguments.contains("DELETE") }
        #expect(apiCall?.arguments == ["api", "-X", "DELETE", "user/gpg_keys/42"])
    }

    @Test
    func uploadKeySendsArmoredKeyAndNameAsJSONStdin() async throws {
        let fake = FakeCommandRunner(result: .ok())
        try await service(fake).uploadKey(armoredPublic: "ARMORED", name: "My Key")

        let post = fake.invocations.first { $0.arguments.contains("POST") }
        #expect(post?.arguments == ["api", "-X", "POST", "--input", "-", "user/gpg_keys"])
        #expect(post?.standardInput?.contains("ARMORED") == true)
        #expect(post?.standardInput?.contains("My Key") == true)
    }
}

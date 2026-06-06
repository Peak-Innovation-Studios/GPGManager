import Testing
@testable import GPGManager

struct GPGAgentServiceTests {
    @Test
    func restartKillsAgentViaGpgconfBesideGpg() async throws {
        let fake = FakeCommandRunner(result: .ok())
        try await GPGAgentService(runner: fake).restart(gpgPath: "/opt/homebrew/bin/gpg")

        #expect(fake.invocations.count == 1)
        #expect(fake.invocations[0].executablePath == "/opt/homebrew/bin/gpgconf")
        #expect(fake.invocations[0].arguments == ["--kill", "gpg-agent"])
    }

    @Test
    func restartThrowsWhenGpgconfFails() async {
        let fake = FakeCommandRunner(result: .failure(stderr: "boom"))
        await #expect(throws: GPGServiceError.self) {
            try await GPGAgentService(runner: fake).restart(gpgPath: "/usr/bin/gpg")
        }
    }
}

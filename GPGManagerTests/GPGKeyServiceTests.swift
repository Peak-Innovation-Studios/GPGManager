import Foundation
import Testing
@testable import GPGManager

struct GPGKeyServiceTests {
    private let gpg = "/usr/bin/gpg"
    private let fingerprint = "0123456789ABCDEF0123456789ABCDEF01234567"

    private var publicListing: String {
        """
        pub:u:4096:1:ABCDEF1234567890:1700000000:1800000000::u:::scESC::::::23::0:
        fpr:::::::::\(fingerprint):
        uid:u::::1700000000::hash::Dev Peak <dev@example.com>::::::::::0:
        """
    }

    private var secretListing: String {
        """
        sec:u:4096:1:ABCDEF1234567890:1700000000::::::::::
        fpr:::::::::\(fingerprint):
        """
    }

    @Test
    func listKeysParsesAndMarksSecret() async throws {
        let fake = FakeCommandRunner { inv in
            inv.arguments.contains("--list-secret-keys")
                ? .ok(stdout: self.secretListing)
                : .ok(stdout: self.publicListing)
        }
        let keys = try await GPGKeyService(runner: fake).listKeys(gpgPath: gpg)

        #expect(keys.count == 1)
        #expect(keys[0].fingerprint == fingerprint)
        #expect(keys[0].keyClass == .secret)
    }

    @Test
    func listKeysThrowsWhenSecretListingFails() async {
        let fake = FakeCommandRunner { inv in
            inv.arguments.contains("--list-secret-keys")
                ? .failure(stderr: "agent busy")
                : .ok(stdout: "")
        }
        await #expect(throws: GPGServiceError.self) {
            _ = try await GPGKeyService(runner: fake).listKeys(gpgPath: self.gpg)
        }
    }

    @Test
    func deleteSecretAndPublicDeletesSecretFirst() async throws {
        let fake = FakeCommandRunner(result: .ok())
        try await GPGKeyService(runner: fake).deleteSecretAndPublicKey(gpgPath: gpg, fingerprint: "FPR")

        #expect(fake.invocations.count == 2)
        #expect(fake.invocations[0].arguments == ["--batch", "--yes", "--delete-secret-keys", "FPR"])
        #expect(fake.invocations[1].arguments == ["--batch", "--yes", "--delete-keys", "FPR"])
    }

    @Test
    func deleteSecretAndPublicStopsWhenSecretDeleteFails() async {
        let fake = FakeCommandRunner { inv in
            inv.arguments.contains("--delete-secret-keys") ? .failure(stderr: "nope") : .ok()
        }
        let service = GPGKeyService(runner: fake)
        await #expect(throws: GPGServiceError.self) {
            try await service.deleteSecretAndPublicKey(gpgPath: self.gpg, fingerprint: "FPR")
        }
        #expect(fake.invocations.count == 1) // public delete never attempted
    }

    @Test
    func createKeyExtractsFingerprintFromRevocationPath() async throws {
        let log = "gpg: revocation certificate stored as '/x/openpgp-revocs.d/\(fingerprint).rev'"
        let fake = FakeCommandRunner(result: .ok(stderr: log))
        var params = GPGCreateKeyParameters()
        params.name = "Dev"
        params.email = "dev@example.com"
        params.passphrase = "pw"

        let result = try await GPGKeyService(runner: fake).createKey(gpgPath: gpg, parameters: params)

        #expect(result.fingerprint == fingerprint)
        #expect(fake.invocations[0].arguments.contains("--gen-key"))
        #expect(fake.invocations[0].standardInput?.contains("Name-Email: dev@example.com") == true)
    }

    @Test
    func fetchAllKeygripsParsesGrips() async throws {
        let keygrip = "1111111111111111111111111111111111111111"
        let output = """
        sec:u:255:22:ABCDEF1234567890:1700000000::::::::::
        fpr:::::::::\(fingerprint):
        grp:::::::::\(keygrip):
        """
        let fake = FakeCommandRunner(result: .ok(stdout: output))
        let grips = try await GPGKeyService(runner: fake).fetchAllKeygrips(gpgPath: gpg, fingerprint: fingerprint)
        #expect(grips == [keygrip])
    }

    @Test
    func fetchAllKeygripsReturnsEmptyOnFailure() async throws {
        let fake = FakeCommandRunner(result: .failure())
        let grips = try await GPGKeyService(runner: fake).fetchAllKeygrips(gpgPath: gpg, fingerprint: "FPR")
        #expect(grips.isEmpty)
    }

    @Test
    func exportPublicKeyReturnsArmoredStdout() async throws {
        let fake = FakeCommandRunner(result: .ok(stdout: "-----BEGIN PGP PUBLIC KEY-----"))
        let armored = try await GPGKeyService(runner: fake).exportPublicKey(gpgPath: gpg, fingerprint: "FPR")

        #expect(armored.hasPrefix("-----BEGIN PGP PUBLIC KEY-----"))
        #expect(fake.invocations[0].arguments == ["--armor", "--export", "FPR"])
    }

    @Test
    func addUserIDBuildsQuickAddCommand() async throws {
        let fake = FakeCommandRunner(result: .ok())
        try await GPGKeyService(runner: fake).addUserID(gpgPath: gpg, fingerprint: "FPR", userID: "New Name <new@example.com>")
        #expect(fake.invocations[0].arguments == ["--batch", "--yes", "--quick-add-uid", "FPR", "New Name <new@example.com>"])
    }
}

import Testing
@testable import GPGManager

struct GPGKeyParserTests {
    @Test
    func parsesPublicKeyWithFingerprintAndUID() {
        let output = """
        tru::1:1700000000:0:3:1:5
        pub:u:4096:1:ABCDEF1234567890:1700000000:1800000000::u:::scESC::::::23::0:
        fpr:::::::::0123456789ABCDEF0123456789ABCDEF01234567:
        uid:u::::1700000000::hash::Dev Peak <dev@example.com>::::::::::0:
        """

        let keys = GPGKeyParser().parsePublicKeys(output)

        #expect(keys.count == 1)
        #expect(keys[0].fingerprint == "0123456789ABCDEF0123456789ABCDEF01234567")
        #expect(keys[0].primaryUserID == "Dev Peak <dev@example.com>")
        #expect(keys[0].keyID == "ABCDEF1234567890")
    }

    @Test
    func marksPublicKeyAsSecretWhenSecretFingerprintMatches() {
        let output = """
        pub:u:4096:1:ABCDEF1234567890:1700000000:::::::::
        fpr:::::::::0123456789ABCDEF0123456789ABCDEF01234567:
        uid:u::::::::Dev Peak <dev@example.com>::::::::::0:
        """

        let keys = GPGKeyParser().parsePublicKeys(output, secretFingerprints: ["0123456789ABCDEF0123456789ABCDEF01234567"])

        #expect(keys[0].keyClass == .secret)
    }
}

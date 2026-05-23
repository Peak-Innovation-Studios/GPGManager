import Testing
@testable import GPGManager

struct GPGCreateKeyParametersTests {
    @Test
    func eccParametersRenderExpectedBatch() {
        var params = GPGCreateKeyParameters()
        params.name = "Dev Peak"
        params.email = "dev@example.com"
        params.algorithm = .ecc
        params.expiration = .oneYear
        params.passphrase = "hunter2"

        let script = params.renderBatchScript()

        #expect(script.contains("Key-Type: EDDSA"))
        #expect(script.contains("Key-Curve: ed25519"))
        #expect(script.contains("Subkey-Type: ECDH"))
        #expect(script.contains("Subkey-Curve: cv25519"))
        #expect(script.contains("Name-Real: Dev Peak"))
        #expect(script.contains("Name-Email: dev@example.com"))
        #expect(script.contains("Expire-Date: 1y"))
        #expect(script.contains("Passphrase: hunter2"))
        #expect(script.contains("%commit"))
    }

    @Test
    func rsa4096RendersKeyLengths() {
        var params = GPGCreateKeyParameters()
        params.name = "Build Bot"
        params.email = "bot@example.com"
        params.algorithm = .rsa4096
        params.expiration = .never
        params.passphrase = "x"

        let script = params.renderBatchScript()

        #expect(script.contains("Key-Type: RSA"))
        #expect(script.contains("Key-Length: 4096"))
        #expect(script.contains("Subkey-Length: 4096"))
        #expect(script.contains("Expire-Date: 0"))
    }

    @Test
    func commentLineOmittedWhenEmpty() {
        var params = GPGCreateKeyParameters()
        params.name = "A"
        params.email = "a@b.co"
        params.passphrase = "p"

        let script = params.renderBatchScript()
        #expect(!script.contains("Name-Comment:"))
    }

    @Test
    func commentLineIncludedWhenProvided() {
        var params = GPGCreateKeyParameters()
        params.name = "A"
        params.email = "a@b.co"
        params.comment = "Signing only"
        params.passphrase = "p"

        let script = params.renderBatchScript()
        #expect(script.contains("Name-Comment: Signing only"))
    }

    @Test
    func validationRequiresNameEmailAndPassphrase() {
        var params = GPGCreateKeyParameters()
        #expect(!params.isValid)

        params.name = "A"
        params.email = "no-at-sign"
        params.passphrase = "p"
        #expect(!params.isValid)

        params.email = "a@b.co"
        #expect(params.isValid)

        params.passphrase = ""
        #expect(!params.isValid)
    }

    @Test
    func validationRequiresDomainAfterAtSign() {
        var params = GPGCreateKeyParameters()
        params.name = "A"
        params.passphrase = "p"

        params.email = "a@"
        #expect(!params.isValid)

        params.email = "a@b"
        #expect(!params.isValid)

        params.email = "a@b.co"
        #expect(params.isValid)
    }
}

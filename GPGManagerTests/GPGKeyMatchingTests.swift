import Foundation
import Testing
@testable import GPGManager

struct GPGKeyMatchingTests {
    private let keys: [GPGKey] = [
        sample(fingerprint: "4E28235F64D543324210B83371731B9AD5674DCF", keyID: "71731B9AD5674DCF"),
        sample(fingerprint: "AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555", keyID: "DDDD4444EEEE5555")
    ]

    @Test
    func matchesFullFingerprint() {
        let result = GPGKey.match(signingKey: "4E28235F64D543324210B83371731B9AD5674DCF", in: keys)
        #expect(result?.keyID == "71731B9AD5674DCF")
    }

    @Test
    func matchesLowercaseFingerprint() {
        let result = GPGKey.match(signingKey: "aaaa1111bbbb2222cccc3333dddd4444eeee5555", in: keys)
        #expect(result?.keyID == "DDDD4444EEEE5555")
    }

    @Test
    func matchesLongKeyID() {
        let result = GPGKey.match(signingKey: "71731B9AD5674DCF", in: keys)
        #expect(result?.keyID == "71731B9AD5674DCF")
    }

    @Test
    func matchesShortKeyIDSuffix() {
        // Standard GPG "short key ID" is the last 8 hex chars of the fingerprint.
        let result = GPGKey.match(signingKey: "D5674DCF", in: keys)
        #expect(result?.keyID == "71731B9AD5674DCF")
    }

    @Test
    func matchesZeroXPrefix() {
        let result = GPGKey.match(signingKey: "0x71731B9AD5674DCF", in: keys)
        #expect(result?.keyID == "71731B9AD5674DCF")
    }

    @Test
    func returnsNilForUnknown() {
        let result = GPGKey.match(signingKey: "DEADBEEF12345678", in: keys)
        #expect(result == nil)
    }

    @Test
    func returnsNilForEmptyOrMissing() {
        #expect(GPGKey.match(signingKey: nil, in: keys) == nil)
        #expect(GPGKey.match(signingKey: "", in: keys) == nil)
        #expect(GPGKey.match(signingKey: "   ", in: keys) == nil)
    }

    private static func sample(fingerprint: String, keyID: String) -> GPGKey {
        GPGKey(
            id: fingerprint,
            keyClass: .secret,
            keyID: keyID,
            fingerprint: fingerprint,
            userIDs: ["Sample <a@b.co>"],
            createdAt: nil,
            expiresAt: nil,
            capabilities: "scESC",
            trust: "u"
        )
    }
}

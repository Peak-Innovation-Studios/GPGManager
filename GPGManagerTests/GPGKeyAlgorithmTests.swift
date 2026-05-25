import Testing
@testable import GPGManager

struct GPGKeyAlgorithmTests {
    @Test
    func rsa4096IsStrongAndOffersNoAdvice() {
        let algo = GPGKeyAlgorithm(code: 1, bitLength: 4096, curveName: nil)
        #expect(algo.displayName == "RSA 4096")
        #expect(algo.strength == .strong)
        #expect(algo.advice == nil)
    }

    @Test
    func rsa2048IsAcceptableWithSuggestion() {
        let algo = GPGKeyAlgorithm(code: 1, bitLength: 2048, curveName: nil)
        #expect(algo.strength == .acceptable)
        #expect(algo.advice?.contains("Ed25519") == true)
    }

    @Test
    func rsa1024IsWeak() {
        let algo = GPGKeyAlgorithm(code: 1, bitLength: 1024, curveName: nil)
        #expect(algo.strength == .weak)
        #expect(algo.advice?.contains("Rotate") == true)
    }

    @Test
    func rsa3072IsStrong() {
        let algo = GPGKeyAlgorithm(code: 1, bitLength: 3072, curveName: nil)
        #expect(algo.strength == .strong)
        #expect(algo.advice == nil)
    }

    @Test
    func dsaIsDeprecated() {
        let algo = GPGKeyAlgorithm(code: 17, bitLength: 2048, curveName: nil)
        #expect(algo.displayName == "DSA 2048")
        #expect(algo.strength == .deprecated)
        #expect(algo.advice != nil)
    }

    @Test
    func elgamalIsDeprecated() {
        let algo = GPGKeyAlgorithm(code: 16, bitLength: 2048, curveName: nil)
        #expect(algo.strength == .deprecated)
    }

    @Test
    func ed25519IsStrongAndNamedSpecially() {
        let algo = GPGKeyAlgorithm(code: 22, bitLength: 256, curveName: "ed25519")
        #expect(algo.displayName == "Ed25519")
        #expect(algo.strength == .strong)
        #expect(algo.advice == nil)
    }

    @Test
    func ecdsaIncludesCurveName() {
        let algo = GPGKeyAlgorithm(code: 19, bitLength: 256, curveName: "nistp256")
        #expect(algo.displayName == "ECDSA (nistp256)")
        #expect(algo.strength == .strong)
    }

    @Test
    func unknownAlgorithmIsHandledGracefully() {
        let algo = GPGKeyAlgorithm(code: 99, bitLength: 0, curveName: nil)
        #expect(algo.displayName == "Algorithm 99")
        #expect(algo.strength == .unknown)
        #expect(algo.advice == nil)
    }
}

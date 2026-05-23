import Testing

struct PassphraseStrengthTests {
    @Test
    func emptyPassphraseScoresZero() {
        #expect(PassphraseStrength.score("") == 0)
    }

    @Test
    func shortAllLowercaseIsWeak() {
        #expect(PassphraseStrength.score("abc") < 25)
    }

    @Test
    func longMixedIsStrong() {
        #expect(PassphraseStrength.score("Tr0ub4dor!Sunset#42") >= 75)
    }

    @Test
    func commonWordsArePenalized() {
        let raw = PassphraseStrength.score("Abc123!")
        let withWeakWord = PassphraseStrength.score("password!Abc123")
        #expect(withWeakWord < raw + 30)
    }

    @Test
    func repeatedSingleCharIsHeavilyPenalized() {
        #expect(PassphraseStrength.score("aaaaaaaaaaaa") < 25)
    }

    @Test
    func scoreNeverExceedsHundredOrGoesNegative() {
        let longRandom = String(repeating: "A1!b2@C3#", count: 8)
        let score = PassphraseStrength.score(longRandom)
        #expect((0...100).contains(score))
    }
}

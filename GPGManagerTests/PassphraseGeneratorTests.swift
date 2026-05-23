import Testing
@testable import GPGManager

struct PassphraseGeneratorTests {
    @Test
    func wordlistHasExpectedSize() {
        #expect(PassphraseGenerator.wordlist.count == 256)
    }

    @Test
    func wordlistHasNoDuplicates() {
        let words = PassphraseGenerator.wordlist
        #expect(Set(words).count == words.count)
    }

    @Test
    func wordlistContainsOnlyLowercaseLetters() {
        for word in PassphraseGenerator.wordlist {
            #expect(word == word.lowercased(), "non-lowercase word: \(word)")
            #expect(word.allSatisfy { $0.isLetter }, "non-letter chars in: \(word)")
        }
    }

    @Test
    func suggestProducesRequestedNumberOfWords() {
        let result = PassphraseGenerator.suggest(wordCount: 8)
        #expect(result.split(separator: "-").count == 8)
    }

    @Test
    func suggestUsesOnlyWordsFromList() {
        let result = PassphraseGenerator.suggest(wordCount: 8)
        let list = Set(PassphraseGenerator.wordlist)
        for piece in result.split(separator: "-") {
            #expect(list.contains(String(piece)), "unexpected word: \(piece)")
        }
    }

    @Test
    func suggestRespectsCustomSeparator() {
        let result = PassphraseGenerator.suggest(wordCount: 4, separator: " ")
        #expect(result.split(separator: " ").count == 4)
        #expect(!result.contains("-"))
    }

    @Test
    func consecutiveSuggestionsArentIdentical() {
        let a = PassphraseGenerator.suggest()
        let b = PassphraseGenerator.suggest()
        #expect(a != b)
    }
}

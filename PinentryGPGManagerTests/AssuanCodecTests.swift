import Testing

struct AssuanCodecTests {
    @Test
    func encodesPercentAndNewlineAndCarriageReturn() {
        #expect(AssuanCodec.encode("100% done") == "100%25 done")
        #expect(AssuanCodec.encode("line1\nline2") == "line1%0Aline2")
        #expect(AssuanCodec.encode("carriage\rreturn") == "carriage%0Dreturn")
    }

    @Test
    func leavesOrdinaryCharactersAlone() {
        #expect(AssuanCodec.encode("Hello, world!") == "Hello, world!")
        #expect(AssuanCodec.encode("café 🔒") == "café 🔒")
    }

    @Test
    func decodesEscapeSequences() {
        #expect(AssuanCodec.decode("Enter%20passphrase") == "Enter passphrase")
        #expect(AssuanCodec.decode("100%25") == "100%")
        #expect(AssuanCodec.decode("line%0Awrap") == "line\nwrap")
    }

    @Test
    func decodesLeavesMalformedEscapesIntact() {
        #expect(AssuanCodec.decode("50%") == "50%")
        #expect(AssuanCodec.decode("50%2") == "50%2")
        #expect(AssuanCodec.decode("50%ZZ") == "50%ZZ")
    }

    @Test
    func roundTripPreservesSpecialCharacters() {
        let original = "Mix of %, \n, and \r in one string"
        #expect(AssuanCodec.decode(AssuanCodec.encode(original)) == original)
    }
}

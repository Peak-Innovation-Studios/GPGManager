import Testing

struct AssuanCommandTests {
    @Test
    func parsesSimpleVerbs() {
        #expect(AssuanCommand.parse("GETPIN") == .getPin)
        #expect(AssuanCommand.parse("BYE") == .bye)
        #expect(AssuanCommand.parse("NOP") == .nop)
        #expect(AssuanCommand.parse("RESET") == .reset)
        #expect(AssuanCommand.parse("MESSAGE") == .message)
    }

    @Test
    func parsesSetCommandsWithArguments() {
        #expect(AssuanCommand.parse("SETDESC Enter passphrase") == .setDesc("Enter passphrase"))
        #expect(AssuanCommand.parse("SETPROMPT Passphrase:") == .setPrompt("Passphrase:"))
        #expect(AssuanCommand.parse("SETKEYINFO n/0xABCD") == .setKeyInfo("n/0xABCD"))
    }

    @Test
    func decodesEscapeSequencesInArguments() {
        #expect(AssuanCommand.parse("SETDESC Hello%0Aworld") == .setDesc("Hello\nworld"))
        #expect(AssuanCommand.parse("SETERROR 50%25 done") == .setError("50% done"))
    }

    @Test
    func parsesOptionInBothEqualsAndSpaceForms() {
        #expect(AssuanCommand.parse("OPTION ttyname=/dev/tty") == .option(key: "ttyname", value: "/dev/tty"))
        #expect(AssuanCommand.parse("OPTION lc-ctype en_US.UTF-8") == .option(key: "lc-ctype", value: "en_US.UTF-8"))
        #expect(AssuanCommand.parse("OPTION no-grab") == .option(key: "no-grab", value: nil))
    }

    @Test
    func parsesConfirmWithOneButtonFlag() {
        #expect(AssuanCommand.parse("CONFIRM") == .confirm(oneButton: false))
        #expect(AssuanCommand.parse("CONFIRM --one-button") == .confirm(oneButton: true))
    }

    @Test
    func parsesGetInfoAndUnknown() {
        #expect(AssuanCommand.parse("GETINFO version") == .getInfo("version"))
        #expect(AssuanCommand.parse("UNHEARD-OF arg") == .unknown(verb: "UNHEARD-OF", argument: "arg"))
    }

    @Test
    func isCaseInsensitiveForVerbs() {
        #expect(AssuanCommand.parse("getpin") == .getPin)
        #expect(AssuanCommand.parse("Bye") == .bye)
    }
}

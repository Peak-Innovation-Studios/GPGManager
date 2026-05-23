import Testing

struct AssuanSessionTests {
    @Test
    func sendsBannerThenAcknowledgesEachCommand() {
        let (output, _) = runScript([
            "OPTION ttyname=/dev/tty",
            "SETDESC Hello",
            "GETPIN",
            "BYE"
        ])

        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines == [
            "OK Pleased to meet you, GPGManager pinentry",
            "OK",
            "OK",
            "D stub-passphrase",
            "OK",
            "OK closing connection"
        ])
    }

    @Test
    func unknownCommandReturnsErr() {
        let (output, _) = runScript(["FROBNICATE foo", "BYE"])
        #expect(output.contains("ERR \(AssuanErrorCode.unknownCommand) "))
    }

    @Test
    func stopsAtBye() {
        let (output, scriptIndex) = runScript(["BYE", "GETPIN"])
        #expect(scriptIndex == 1)
        #expect(output.contains("OK closing connection"))
        #expect(!output.contains("D stub-passphrase"))
    }

    private func runScript(_ commands: [String]) -> (output: String, consumed: Int) {
        var queue = commands
        var consumed = 0
        var output = ""

        let session = AssuanSession(
            read: {
                guard !queue.isEmpty else { return nil }
                consumed += 1
                return queue.removeFirst()
            },
            write: { output += $0 },
            handler: StubPinentryHandler()
        )

        session.run()
        return (output, consumed)
    }
}

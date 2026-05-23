import Testing
@testable import GPGManager

struct GPGAgentConfigStoreTests {
    @Test
    func parsesKnownAgentSettingsAndPreservesOtherLines() {
        let text = """
        # comment
        default-cache-ttl 600
        max-cache-ttl 7200
        pinentry-program /opt/homebrew/bin/pinentry-mac
        allow-preset-passphrase
        """

        let config = GPGAgentConfigStore().parse(text)

        #expect(config.defaultCacheTTL == 600)
        #expect(config.maxCacheTTL == 7200)
        #expect(config.pinentryProgram == "/opt/homebrew/bin/pinentry-mac")
        #expect(config.extraLines.contains("# comment"))
        #expect(config.extraLines.contains("allow-preset-passphrase"))
    }

    @Test
    func rendersKnownSettingsOnce() {
        let config = GPGAgentConfig(
            defaultCacheTTL: 300,
            maxCacheTTL: 900,
            pinentryProgram: "/usr/local/MacGPG2/libexec/pinentry-mac.app/Contents/MacOS/pinentry-mac",
            extraLines: ["# comment", "default-cache-ttl 1"]
        )

        let rendered = GPGAgentConfigStore().render(config)

        #expect(rendered.contains("# comment"))
        #expect(rendered.contains("default-cache-ttl 300"))
        #expect(!rendered.contains("default-cache-ttl 1"))
    }
}

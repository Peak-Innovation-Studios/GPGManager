import Testing
@testable import GPGManager

struct GPGConfigStoreTests {
    @Test
    func parsesDefaultKeyAndKeyserver() {
        let text = """
        # personal config
        default-key 0123456789ABCDEF
        keyserver hkps://keys.openpgp.org
        keyserver-options auto-key-retrieve
        """

        let config = GPGConfigStore().parse(text)

        #expect(config.defaultKey == "0123456789ABCDEF")
        #expect(config.keyserver == "hkps://keys.openpgp.org")
        #expect(config.autoKeyRetrieve == true)
        #expect(config.extraLines.contains("# personal config"))
    }

    @Test
    func roundTripPreservesValuesAndDropsLegacyLines() {
        let original = """
        default-key OLDKEY
        keyserver hkps://old.example.com
        keyserver-options auto-key-retrieve no-honor-keyserver-url
        utf8-strings
        """

        let store = GPGConfigStore()
        var config = store.parse(original)
        config.defaultKey = "ABCDEF0123456789"
        config.keyserver = "hkps://keys.openpgp.org"
        config.autoKeyRetrieve = false

        let rendered = store.render(config)

        #expect(rendered.contains("default-key ABCDEF0123456789"))
        #expect(rendered.contains("keyserver hkps://keys.openpgp.org"))
        #expect(!rendered.contains("default-key OLDKEY"))
        #expect(!rendered.contains("keyserver hkps://old.example.com"))
        #expect(!rendered.contains("auto-key-retrieve"))
        #expect(rendered.contains("utf8-strings"))
        #expect(rendered.contains("no-honor-keyserver-url"))
    }

    @Test
    func clearingValuesRemovesThemFromOutput() {
        var config = GPGConfig.empty
        config.defaultKey = nil
        config.keyserver = nil
        config.autoKeyRetrieve = false

        let rendered = GPGConfigStore().render(config)

        #expect(!rendered.contains("default-key"))
        #expect(!rendered.contains("keyserver"))
    }
}

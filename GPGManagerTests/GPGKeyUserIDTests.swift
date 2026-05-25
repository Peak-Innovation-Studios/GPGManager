import Testing
@testable import GPGManager

struct GPGKeyUserIDTests {
    @Test
    func parsesNameAndEmail() {
        let parts = GPGKey.parseUserID("David Peak <dppeak@yahoo.com>")
        #expect(parts.name == "David Peak")
        #expect(parts.email == "dppeak@yahoo.com")
        #expect(parts.comment == "")
    }

    @Test
    func parsesNameCommentAndEmail() {
        let parts = GPGKey.parseUserID("David Peak (Work) <david.peak@vml.com>")
        #expect(parts.name == "David Peak")
        #expect(parts.comment == "Work")
        #expect(parts.email == "david.peak@vml.com")
    }

    @Test
    func handlesMalformedUserIDsGracefully() {
        let parts = GPGKey.parseUserID("Just a Name")
        #expect(parts.name == "Just a Name")
        #expect(parts.comment == "")
        #expect(parts.email == "")
    }

    @Test
    func formattedRoundTripsWithoutComment() {
        let parts = GPGKey.UserIDParts(name: "David Peak", comment: "", email: "dppeak@yahoo.com")
        #expect(parts.formatted == "David Peak <dppeak@yahoo.com>")
    }

    @Test
    func formattedIncludesCommentWhenProvided() {
        let parts = GPGKey.UserIDParts(name: "David Peak", comment: "Work", email: "david.peak@vml.com")
        #expect(parts.formatted == "David Peak (Work) <david.peak@vml.com>")
    }

    @Test
    func formattedTrimsWhitespace() {
        let parts = GPGKey.UserIDParts(name: "  David  ", comment: "  Work ", email: "  d@v.com ")
        #expect(parts.formatted == "David (Work) <d@v.com>")
    }
}

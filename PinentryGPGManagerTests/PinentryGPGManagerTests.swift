import Testing

struct AssuanResponseTests {
    @Test
    func rendersOkVariants() {
        #expect(AssuanResponse.ok(message: nil).wireFormat == "OK\n")
        #expect(AssuanResponse.ok(message: "hello").wireFormat == "OK hello\n")
    }

    @Test
    func rendersErrCode() {
        #expect(AssuanResponse.err(code: 99, description: "cancelled").wireFormat == "ERR 99 cancelled\n")
    }

    @Test
    func encodesDataPayload() {
        #expect(AssuanResponse.data("secret").wireFormat == "D secret\n")
        #expect(AssuanResponse.data("100% sure").wireFormat == "D 100%25 sure\n")
        #expect(AssuanResponse.data("multi\nline").wireFormat == "D multi%0Aline\n")
    }

    @Test
    func canceledErrorCodeIsStandardPinentryValue() {
        #expect(AssuanErrorCode.canceled == 83886179)
    }
}

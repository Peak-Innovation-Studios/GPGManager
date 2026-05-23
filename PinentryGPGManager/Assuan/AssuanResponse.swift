import Foundation

enum AssuanResponse: Equatable {
    case ok(message: String?)
    case err(code: UInt32, description: String)
    case data(String)
    case status(keyword: String, info: String?)
    case comment(String)
    case inquire(keyword: String, info: String?)

    var wireFormat: String {
        switch self {
        case .ok(let message):
            if let message, !message.isEmpty {
                return "OK \(message)\n"
            }
            return "OK\n"
        case .err(let code, let description):
            return "ERR \(code) \(description)\n"
        case .data(let value):
            return "D \(AssuanCodec.encode(value))\n"
        case .status(let keyword, let info):
            if let info, !info.isEmpty {
                return "S \(keyword) \(info)\n"
            }
            return "S \(keyword)\n"
        case .comment(let text):
            return "# \(text)\n"
        case .inquire(let keyword, let info):
            if let info, !info.isEmpty {
                return "INQUIRE \(keyword) \(info)\n"
            }
            return "INQUIRE \(keyword)\n"
        }
    }
}

enum AssuanErrorCode {
    static let source: UInt32 = 5
    static let canceled = make(99)
    static let notConfirmed = make(114)
    static let badPassphrase = make(11)
    static let unknownCommand = make(275)
    static let notImplemented = make(69)

    static func make(_ code: UInt32) -> UInt32 {
        (source << 24) | code
    }
}

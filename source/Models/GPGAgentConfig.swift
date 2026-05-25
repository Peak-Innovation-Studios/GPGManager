import Foundation

struct GPGAgentConfig: Equatable {
    var defaultCacheTTL: Int?
    var maxCacheTTL: Int?
    var pinentryProgram: String?
    var extraLines: [String]

    static let empty = GPGAgentConfig(defaultCacheTTL: nil, maxCacheTTL: nil, pinentryProgram: nil, extraLines: [])
}

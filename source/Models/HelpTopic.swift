import Foundation

struct HelpTopic: Identifiable, Hashable {
    enum Category: String, CaseIterable, Hashable {
        case gettingStarted = "Getting Started"
        case features       = "Features"
        case configuration  = "Configuration"
        case reference      = "Reference"
    }

    let id: String
    let title: String
    let summary: String
    let systemImage: String
    let category: Category
    let sections: [HelpSection]
}

struct HelpSection: Hashable {
    let heading: String?
    let blocks: [HelpBlock]

    init(_ blocks: [HelpBlock]) {
        self.heading = nil
        self.blocks = blocks
    }

    init(_ heading: String, _ blocks: [HelpBlock]) {
        self.heading = heading
        self.blocks = blocks
    }
}

enum HelpBlock: Hashable {
    case paragraph(String)
    case bullets([String])
    case steps([String])
    case code(String, caption: String? = nil)
    case tip(String)
    case note(String)
    case warning(String)
    case keyValue([(String, String)])

    func hash(into hasher: inout Hasher) {
        switch self {
        case .paragraph(let s):    hasher.combine(0); hasher.combine(s)
        case .bullets(let xs):     hasher.combine(1); hasher.combine(xs)
        case .steps(let xs):       hasher.combine(2); hasher.combine(xs)
        case .code(let c, let t):  hasher.combine(3); hasher.combine(c); hasher.combine(t)
        case .tip(let s):          hasher.combine(4); hasher.combine(s)
        case .note(let s):         hasher.combine(5); hasher.combine(s)
        case .warning(let s):      hasher.combine(6); hasher.combine(s)
        case .keyValue(let pairs):
            hasher.combine(7)
            for (k, v) in pairs { hasher.combine(k); hasher.combine(v) }
        }
    }

    static func == (lhs: HelpBlock, rhs: HelpBlock) -> Bool {
        switch (lhs, rhs) {
        case (.paragraph(let a), .paragraph(let b)):    return a == b
        case (.bullets(let a), .bullets(let b)):      return a == b
        case (.steps(let a), .steps(let b)):        return a == b
        case (.code(let a, let ac), .code(let b, let bc)): return a == b && ac == bc
        case (.tip(let a), .tip(let b)):          return a == b
        case (.note(let a), .note(let b)):         return a == b
        case (.warning(let a), .warning(let b)):      return a == b
        case (.keyValue(let a), .keyValue(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }
}

enum HelpContent {
    static var allTopics: [HelpTopic] {
        [
            .welcome,
            .gettingStarted,
            .creatingKeys,
            .overviewTab,
            .gitSigning,
            .gitHubKeys,
            .publicKeysWindow,
            .passphraseAndTouchID,
            .keyServer,
            .pinentryHelper,
            .menusAndShortcuts,
            .troubleshooting
        ]
    }

    static func topic(id: String) -> HelpTopic? {
        allTopics.first { $0.id == id }
    }

    static func topics(in category: HelpTopic.Category) -> [HelpTopic] {
        allTopics.filter { $0.category == category }
    }
}

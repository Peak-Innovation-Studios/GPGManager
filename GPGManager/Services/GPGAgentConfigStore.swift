import Foundation

struct GPGAgentConfigStore {
    let configURL: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.configURL = homeDirectory
            .appending(path: ".gnupg", directoryHint: .isDirectory)
            .appending(path: "gpg-agent.conf")
    }

    func load() throws -> GPGAgentConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .empty
        }

        let text = try String(contentsOf: configURL, encoding: .utf8)
        return parse(text)
    }

    func save(_ config: GPGAgentConfig) throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try render(config).write(to: configURL, atomically: true, encoding: .utf8)
    }

    func parse(_ text: String) -> GPGAgentConfig {
        var config = GPGAgentConfig.empty

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                config.extraLines.append(line)
                continue
            }

            let pieces = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            switch pieces.first {
            case "default-cache-ttl":
                config.defaultCacheTTL = pieces.dropFirst().first.flatMap(Int.init)
            case "max-cache-ttl":
                config.maxCacheTTL = pieces.dropFirst().first.flatMap(Int.init)
            case "pinentry-program":
                config.pinentryProgram = pieces.dropFirst().first
            default:
                config.extraLines.append(line)
            }
        }

        return config
    }

    func render(_ config: GPGAgentConfig) -> String {
        var lines = config.extraLines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("default-cache-ttl")
                && !trimmed.hasPrefix("max-cache-ttl")
                && !trimmed.hasPrefix("pinentry-program")
        }

        if let defaultCacheTTL = config.defaultCacheTTL {
            lines.append("default-cache-ttl \(defaultCacheTTL)")
        }
        if let maxCacheTTL = config.maxCacheTTL {
            lines.append("max-cache-ttl \(maxCacheTTL)")
        }
        if let pinentryProgram = config.pinentryProgram, !pinentryProgram.isEmpty {
            lines.append("pinentry-program \(pinentryProgram)")
        }

        return lines.joined(separator: "\n") + "\n"
    }
}

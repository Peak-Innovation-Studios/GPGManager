import Foundation

struct GPGConfigStore {
    let configURL: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.configURL = homeDirectory
            .appending(path: ".gnupg", directoryHint: .isDirectory)
            .appending(path: "gpg.conf")
    }

    func load() throws -> GPGConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .empty
        }
        let text = try String(contentsOf: configURL, encoding: .utf8)
        return parse(text)
    }

    func save(_ config: GPGConfig) throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try render(config).write(to: configURL, atomically: true, encoding: .utf8)
    }

    func parse(_ text: String) -> GPGConfig {
        var config = GPGConfig.empty

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                config.extraLines.append(line)
                continue
            }

            let pieces = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            let keyword = pieces.first ?? ""
            let argument = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespaces) : ""

            switch keyword {
            case "default-key":
                config.defaultKey = argument.isEmpty ? nil : argument
            case "keyserver":
                config.keyserver = argument.isEmpty ? nil : argument
            case "keyserver-options":
                let options = argument.split(separator: " ").map(String.init)
                if options.contains("auto-key-retrieve") {
                    config.autoKeyRetrieve = true
                }
                let preserved = options.filter { $0 != "auto-key-retrieve" && $0 != "no-auto-key-retrieve" }
                config.preservedKeyserverOptions.append(contentsOf: preserved)
            default:
                config.extraLines.append(line)
            }
        }

        return config
    }

    func render(_ config: GPGConfig) -> String {
        var lines = config.extraLines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("default-key")
                && !trimmed.hasPrefix("keyserver ")
                && trimmed != "keyserver"
                && !trimmed.hasPrefix("keyserver-options")
        }

        if let defaultKey = config.defaultKey, !defaultKey.isEmpty {
            lines.append("default-key \(defaultKey)")
        }
        if let keyserver = config.keyserver, !keyserver.isEmpty {
            lines.append("keyserver \(keyserver)")
        }
        var keyserverOptions = config.preservedKeyserverOptions
        if config.autoKeyRetrieve {
            keyserverOptions.insert("auto-key-retrieve", at: 0)
        }
        if !keyserverOptions.isEmpty {
            lines.append("keyserver-options " + keyserverOptions.joined(separator: " "))
        }

        return lines.joined(separator: "\n") + "\n"
    }
}

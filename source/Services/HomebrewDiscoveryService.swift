import Foundation

struct HomebrewDiscoveryService {
    var fileIsExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    var pathEnvironment: () -> String = { ProcessInfo.processInfo.environment["PATH"] ?? "" }

    /// Returns the absolute path to a `brew` binary if one can be found, otherwise `nil`.
    func discoverBrewPath() -> String? {
        let standardCandidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        for candidate in standardCandidates where fileIsExecutable(candidate) {
            return candidate
        }

        let pathDirs = pathEnvironment().split(separator: ":").map(String.init)
        for dir in pathDirs {
            let candidate = URL(fileURLWithPath: dir).appending(path: "brew").path
            if fileIsExecutable(candidate) {
                return candidate
            }
        }

        return nil
    }
}

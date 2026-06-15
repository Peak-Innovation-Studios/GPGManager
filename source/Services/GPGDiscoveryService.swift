import Foundation

struct GPGDiscoveryService {
    private let runner = GPGCommandRunner()

    func discover() async -> [GPGInstallation] {
        var candidates: [GPGInstallation] = [
            GPGInstallation(path: "/usr/local/MacGPG2/bin/gpg", kind: .macGPG2),
            GPGInstallation(path: "/opt/homebrew/bin/gpg", kind: .homebrew),
            GPGInstallation(path: "/usr/local/bin/gpg", kind: .homebrew),
            GPGInstallation(path: "/usr/bin/gpg", kind: .path)
        ]

        for path in pathCandidates(named: "gpg") where !candidates.contains(where: { $0.path == path }) {
            candidates.append(GPGInstallation(path: path, kind: .path))
        }

        var found: [GPGInstallation] = []
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            var installation = candidate
            installation.version = await version(for: candidate.path)
            found.append(installation)
        }
        return found
    }

    private func version(for path: String) async -> String? {
        guard let result = try? await runner.run(executablePath: path, arguments: ["--version"]), result.succeeded else {
            return nil
        }
        return result.stdout.components(separatedBy: .newlines).first
    }

    private func pathCandidates(named executableName: String) -> [String] {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(executableName).path }
    }
}

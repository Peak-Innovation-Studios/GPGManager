import Foundation

struct GPGAgentService {
    private let runner: any CommandRunning

    init(runner: any CommandRunning = GPGCommandRunner()) {
        self.runner = runner
    }

    func restart(gpgPath: String) async throws {
        let gpgconfPath = gpgconfPath(for: gpgPath)
        let result = try await runner.run(executablePath: gpgconfPath, arguments: ["--kill", "gpg-agent"])
        guard result.succeeded else {
            throw GPGServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    private func gpgconfPath(for gpgPath: String) -> String {
        URL(fileURLWithPath: gpgPath)
            .deletingLastPathComponent()
            .appendingPathComponent("gpgconf")
            .path
    }
}

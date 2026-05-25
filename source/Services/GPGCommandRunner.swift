import Foundation

struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool {
        exitCode == 0
    }
}

enum CommandRunnerError: LocalizedError {
    case missingExecutable(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let path):
            "Executable not found at \(path)"
        case .launchFailed(let message):
            message
        }
    }
}

struct GPGCommandRunner {
    func run(
        executablePath: String,
        arguments: [String],
        standardInput: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw CommandRunnerError.missingExecutable(executablePath)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            if let standardInput {
                let inputPipe = Pipe()
                process.standardInput = inputPipe
                if let data = standardInput.data(using: .utf8) {
                    try? inputPipe.fileHandleForWriting.write(contentsOf: data)
                }
                try? inputPipe.fileHandleForWriting.close()
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: CommandRunnerError.launchFailed(error.localizedDescription))
                return
            }

            process.terminationHandler = { process in
                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let result = CommandResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: output, encoding: .utf8) ?? "",
                    stderr: String(data: error, encoding: .utf8) ?? ""
                )
                continuation.resume(returning: result)
            }
        }
    }
}

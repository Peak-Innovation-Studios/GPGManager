import Foundation

enum AssuanCommandResult: Equatable {
    case ok(message: String?)
    case error(code: UInt32, description: String)
    case data(String)
    case bye
}

protocol AssuanHandler {
    func handle(_ command: AssuanCommand) -> AssuanCommandResult
}

struct StubPinentryHandler: AssuanHandler {
    var passphrase: String = "stub-passphrase"

    func handle(_ command: AssuanCommand) -> AssuanCommandResult {
        switch command {
        case .bye:
            return .bye
        case .getPin:
            return .data(passphrase)
        case .confirm:
            return .ok(message: nil)
        case .getInfo(let what):
            switch what.lowercased() {
            case "pid":     return .data(String(ProcessInfo.processInfo.processIdentifier))
            case "version": return .data("1.0")
            case "flavor":  return .data("gpgmanager")
            default:        return .error(code: AssuanErrorCode.notImplemented, description: "Unknown GETINFO \(what)")
            }
        case .nop, .reset, .message:
            return .ok(message: nil)
        case .option,
             .setDesc, .setPrompt, .setKeyInfo, .setTitle,
             .setOK, .setCancel, .setNotOK, .setError,
             .setRepeat, .setRepeatError,
             .setQualityBar, .setQualityBarTooltip:
            return .ok(message: nil)
        case .unknown(let verb, _):
            return .error(code: AssuanErrorCode.unknownCommand, description: "Unknown command \(verb)")
        }
    }
}

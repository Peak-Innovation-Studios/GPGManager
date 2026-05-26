import Foundation

enum AssuanCommand: Equatable {
    case option(key: String, value: String?)
    case setDesc(String)
    case setPrompt(String)
    case setKeyInfo(String)
    case setTitle(String)
    case setOK(String)
    case setCancel(String)
    case setNotOK(String)
    case setError(String)
    case setRepeat(String?)
    case setRepeatError(String)
    case setQualityBar(String?)
    case setQualityBarTooltip(String)
    case message
    case confirm(oneButton: Bool)
    case getPin
    case getInfo(String)
    case nop
    case reset
    case bye
    case unknown(verb: String, argument: String?)

    nonisolated static func parse(_ line: String) -> AssuanCommand {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unknown(verb: "", argument: nil)
        }

        let split = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let verb = split[0].uppercased()
        let rawArgument = split.count > 1 ? split[1] : nil
        let argument = rawArgument.map(AssuanCodec.decode)

        switch verb {
        case "OPTION":
            return parseOption(rawArgument ?? "")
        case "SETDESC":         return .setDesc(argument ?? "")
        case "SETPROMPT":       return .setPrompt(argument ?? "")
        case "SETKEYINFO":      return .setKeyInfo(argument ?? "")
        case "SETTITLE":        return .setTitle(argument ?? "")
        case "SETOK":           return .setOK(argument ?? "")
        case "SETCANCEL":       return .setCancel(argument ?? "")
        case "SETNOTOK":        return .setNotOK(argument ?? "")
        case "SETERROR":        return .setError(argument ?? "")
        case "SETREPEAT":       return .setRepeat(argument)
        case "SETREPEATERROR":  return .setRepeatError(argument ?? "")
        case "SETQUALITYBAR":   return .setQualityBar(argument)
        case "SETQUALITYBAR_TT": return .setQualityBarTooltip(argument ?? "")
        case "MESSAGE":         return .message
        case "CONFIRM":         return .confirm(oneButton: (rawArgument ?? "").contains("--one-button"))
        case "GETPIN":          return .getPin
        case "GETINFO":         return .getInfo(argument ?? "")
        case "NOP":             return .nop
        case "RESET":           return .reset
        case "BYE":             return .bye
        default:                return .unknown(verb: verb, argument: argument)
        }
    }

    nonisolated private static func parseOption(_ argument: String) -> AssuanCommand {
        let trimmed = argument.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .option(key: "", value: nil) }

        if let equals = trimmed.firstIndex(of: "=") {
            let key = String(trimmed[..<equals])
            let value = String(trimmed[trimmed.index(after: equals)...])
            return .option(key: key, value: AssuanCodec.decode(value))
        }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let key = parts[0]
        let value = parts.count > 1 ? AssuanCodec.decode(parts[1]) : nil
        return .option(key: key, value: value)
    }
}

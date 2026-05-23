import Foundation

final class AssuanSession {
    private let read: () -> String?
    private let write: (String) -> Void
    private let handler: AssuanHandler

    init(read: @escaping () -> String?, write: @escaping (String) -> Void, handler: AssuanHandler) {
        self.read = read
        self.write = write
        self.handler = handler
    }

    func run() {
        send(.ok(message: "Pleased to meet you, GPGManager pinentry"))

        while let line = read() {
            if line.isEmpty { continue }
            let command = AssuanCommand.parse(line)
            switch handler.handle(command) {
            case .ok(let message):
                send(.ok(message: message))
            case .error(let code, let description):
                send(.err(code: code, description: description))
            case .data(let payload):
                send(.data(payload))
                send(.ok(message: nil))
            case .bye:
                send(.ok(message: "closing connection"))
                return
            }
        }
    }

    private func send(_ response: AssuanResponse) {
        write(response.wireFormat)
    }
}

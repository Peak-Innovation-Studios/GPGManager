import Foundation

final class AssuanLineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func readLine() -> String? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                let line = String(data: lineData, encoding: .utf8) ?? ""
                return stripCarriageReturn(line)
            }

            let chunk = handle.availableData
            if chunk.isEmpty {
                if buffer.isEmpty { return nil }
                let line = String(data: buffer, encoding: .utf8) ?? ""
                buffer.removeAll()
                return stripCarriageReturn(line)
            }
            buffer.append(chunk)
        }
    }

    private func stripCarriageReturn(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }
}

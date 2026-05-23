import Foundation

enum AssuanCodec {
    static func encode(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "%": out.append("%25")
            case "\n": out.append("%0A")
            case "\r": out.append("%0D")
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    static func decode(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)

        var i = string.startIndex
        while i < string.endIndex {
            let c = string[i]
            if c == "%",
               let next1 = string.index(i, offsetBy: 1, limitedBy: string.endIndex),
               let next2 = string.index(i, offsetBy: 2, limitedBy: string.endIndex),
               next1 < string.endIndex, next2 < string.endIndex {
                let hex = String(string[next1...next2])
                if let value = UInt8(hex, radix: 16),
                   let scalar = Unicode.Scalar(UInt32(value)) {
                    out.unicodeScalars.append(scalar)
                    i = string.index(after: next2)
                    continue
                }
            }
            out.append(c)
            i = string.index(after: i)
        }
        return out
    }
}

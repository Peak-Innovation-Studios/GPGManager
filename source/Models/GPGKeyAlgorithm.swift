import Foundation

/// Public-key algorithm metadata as reported by GPG's colon-format output.
/// Algorithm codes follow RFC 4880 / 9580. Curve names are populated for ECC variants.
struct GPGKeyAlgorithm: Equatable, Hashable {
    enum Strength {
        case strong       // ECC / RSA 3072+
        case acceptable   // RSA 2048
        case weak         // RSA 1024–2047
        case deprecated   // DSA, Elgamal, RSA <1024
        case unknown
    }

    let code: Int
    let bitLength: Int
    let curveName: String?

    var displayName: String {
        switch code {
        case 1, 2, 3:
            return bitLength > 0 ? "RSA \(bitLength)" : "RSA"
        case 16:
            return bitLength > 0 ? "Elgamal \(bitLength)" : "Elgamal"
        case 17:
            return bitLength > 0 ? "DSA \(bitLength)" : "DSA"
        case 18:
            return curveName.map { "ECDH (\($0))" } ?? "ECDH"
        case 19:
            return curveName.map { "ECDSA (\($0))" } ?? "ECDSA"
        case 22:
            if let curveName, curveName.localizedCaseInsensitiveContains("ed25519") {
                return "Ed25519"
            }
            return curveName.map { "EdDSA (\($0))" } ?? "EdDSA"
        case 23:
            return "AEDH"
        case 24:
            return "AEDSA"
        case 0:
            return "Unknown"
        default:
            return "Algorithm \(code)"
        }
    }

    var strength: Strength {
        switch code {
        case 1, 2, 3:
            if bitLength == 0 { return .unknown }
            if bitLength < 1024 { return .deprecated }
            if bitLength < 2048 { return .weak }
            if bitLength < 3072 { return .acceptable }
            return .strong
        case 16, 17:
            return .deprecated
        case 18, 19, 22, 23, 24:
            return .strong
        default:
            return .unknown
        }
    }

    /// Plain-English advice when the algorithm/length is below current best practice.
    /// Returns nil for `.strong` and `.unknown`.
    var advice: String? {
        switch strength {
        case .strong, .unknown:
            return nil
        case .acceptable:
            return "RSA \(bitLength) still works, but RSA 4096 or Ed25519 are more future-proof for new keys."
        case .weak:
            return "RSA \(bitLength) is below current recommendations. Rotate to RSA 4096 or Ed25519."
        case .deprecated:
            return "\(displayName) is considered deprecated. Rotate to RSA 4096 or Ed25519."
        }
    }
}

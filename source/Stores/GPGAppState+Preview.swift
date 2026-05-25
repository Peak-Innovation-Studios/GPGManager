#if DEBUG
import Foundation

@MainActor
extension GPGAppState {
    static var preview: GPGAppState {
        let state = GPGAppState()
        state.installations = Self.sampleInstallations
        state.selectedGPGPath = Self.sampleInstallations[0].path
        state.keys = Self.sampleKeys
        state.selectedKeyID = Self.sampleKeys.first?.id
        state.agentConfig = GPGAgentConfig(
            defaultCacheTTL: 600,
            maxCacheTTL: 7200,
            pinentryProgram: "/opt/homebrew/bin/pinentry-mac",
            extraLines: ["allow-preset-passphrase"]
        )
        state.gpgConfig = GPGConfig(
            defaultKey: Self.sampleKeys[0].keyID,
            keyserver: GPGKeyserverPreset.openPGP.rawValue,
            autoKeyRetrieve: true,
            preservedKeyserverOptions: [],
            extraLines: []
        )
        state.gitGPGProgram = Self.sampleInstallations[0].path
        state.statusMessage = "Loaded \(Self.sampleKeys.count) keys."
        return state
    }

    static var previewEmpty: GPGAppState {
        let state = GPGAppState()
        state.statusMessage = "No GPG executable selected."
        return state
    }

    private static let sampleInstallations: [GPGInstallation] = [
        GPGInstallation(path: "/usr/local/MacGPG2/bin/gpg", kind: .macGPG2, version: "gpg (GnuPG/MacGPG2) 2.2.41"),
        GPGInstallation(path: "/opt/homebrew/bin/gpg", kind: .homebrew, version: "gpg (GnuPG) 2.4.5")
    ]

    private static let sampleKeys: [GPGKey] = [
        GPGKey(
            id: "0123456789ABCDEF0123456789ABCDEF01234567",
            keyClass: .secret,
            keyID: "ABCDEF1234567890",
            fingerprint: "0123456789ABCDEF0123456789ABCDEF01234567",
            userIDs: ["Dev Peak <dev@example.com>", "Dev Peak <dev@peakinnovationstudios.com>"],
            createdAt: Date(timeIntervalSinceReferenceDate: 700_000_000),
            expiresAt: Date(timeIntervalSinceReferenceDate: 900_000_000),
            capabilities: "scESC",
            trust: "u",
            algorithmCode: 1,
            bitLength: 4096
        ),
        GPGKey(
            id: "AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555",
            keyClass: .public,
            keyID: "BBBBCCCC22223333",
            fingerprint: "AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555",
            userIDs: ["Alice Example <alice@example.com>"],
            createdAt: Date(timeIntervalSinceReferenceDate: 650_000_000),
            expiresAt: nil,
            capabilities: "sc",
            trust: "f",
            algorithmCode: 1,
            bitLength: 2048
        ),
        GPGKey(
            id: "9999AAAA8888BBBB7777CCCC6666DDDD5555EEEE",
            keyClass: .secret,
            keyID: "1111222233334444",
            fingerprint: "9999AAAA8888BBBB7777CCCC6666DDDD5555EEEE",
            userIDs: ["Build Bot <bot@example.com>"],
            createdAt: Date(timeIntervalSinceReferenceDate: 750_000_000),
            expiresAt: Date(timeIntervalSinceReferenceDate: 850_000_000),
            capabilities: "s",
            trust: "u",
            algorithmCode: 22,
            bitLength: 256,
            curveName: "ed25519"
        )
    ]
}
#endif

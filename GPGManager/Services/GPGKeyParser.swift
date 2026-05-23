import Foundation

struct GPGKeyParser {
    func parsePublicKeys(_ text: String, secretFingerprints: Set<String> = []) -> [GPGKey] {
        parse(text, defaultClass: .public).map { key in
            var updated = key
            if secretFingerprints.contains(key.fingerprint) {
                updated.keyClass = .secret
            }
            return updated
        }
    }

    func parseSecretFingerprints(_ text: String) -> Set<String> {
        Set(parse(text, defaultClass: .secret).map(\.fingerprint))
    }

    /// Returns the first `grp:` record's keygrip from a `--with-colons --with-keygrip`
    /// listing — i.e., the primary key's keygrip when the input lists a single key.
    func parsePrimaryKeygrip(_ text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let fields = line.components(separatedBy: ":")
            if fields.first == "grp", fields.count > 9 {
                let value = fields[9]
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func parse(_ text: String, defaultClass: GPGKey.KeyClass) -> [GPGKey] {
        var keys: [GPGKey] = []
        var current: PartialKey?

        for line in text.components(separatedBy: .newlines) {
            let fields = line.components(separatedBy: ":")
            guard let record = fields.first else { continue }

            switch record {
            case "pub", "sec":
                if let key = current?.materialize() {
                    keys.append(key)
                }
                current = PartialKey(
                    keyClass: record == "sec" ? .secret : defaultClass,
                    keyID: value(at: 4, in: fields),
                    createdAt: date(at: 5, in: fields),
                    expiresAt: date(at: 6, in: fields),
                    capabilities: value(at: 11, in: fields),
                    trust: value(at: 1, in: fields)
                )
            case "fpr":
                guard current?.fingerprint == nil else { continue }
                current?.fingerprint = value(at: 9, in: fields)
            case "uid":
                let uid = value(at: 9, in: fields)
                if !uid.isEmpty {
                    current?.userIDs.append(uid)
                }
            default:
                continue
            }
        }

        if let key = current?.materialize() {
            keys.append(key)
        }

        return keys
    }

    private func value(at index: Int, in fields: [String]) -> String {
        guard fields.indices.contains(index) else { return "" }
        return fields[index]
    }

    private func date(at index: Int, in fields: [String]) -> Date? {
        guard let timestamp = TimeInterval(value(at: index, in: fields)), timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }
}

private struct PartialKey {
    var keyClass: GPGKey.KeyClass
    var keyID: String
    var createdAt: Date?
    var expiresAt: Date?
    var capabilities: String
    var trust: String
    var fingerprint: String?
    var userIDs: [String] = []

    func materialize() -> GPGKey? {
        guard let fingerprint, !fingerprint.isEmpty else { return nil }
        return GPGKey(
            id: fingerprint,
            keyClass: keyClass,
            keyID: keyID,
            fingerprint: fingerprint,
            userIDs: userIDs,
            createdAt: createdAt,
            expiresAt: expiresAt,
            capabilities: capabilities,
            trust: trust
        )
    }
}

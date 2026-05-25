import Foundation

struct GitSigningConfiguration: Equatable {
    var signingKey: String?
    var gpgProgram: String?
    var signsCommits: Bool
    var signsTags: Bool
    /// `log.showSignature` — when true, `git log` includes signature info.
    var showsLogSignatures: Bool = false
    /// Effective `user.name` — merged from system/global/local when applicable.
    var userName: String?
    /// Effective `user.email` — merged from system/global/local when applicable.
    var userEmail: String?
    /// Per-field flags indicating whether the repository's local config sets
    /// that field. Only meaningful for `.repository` scope; always false for `.global`.
    var userOverriddenLocally: Bool = false
    var signingKeyOverriddenLocally: Bool = false
    var signsCommitsOverriddenLocally: Bool = false
    var signsTagsOverriddenLocally: Bool = false
    var showsLogSignaturesOverriddenLocally: Bool = false

    static let empty = GitSigningConfiguration(
        signingKey: nil,
        gpgProgram: nil,
        signsCommits: false,
        signsTags: false,
        userName: nil,
        userEmail: nil
    )
}

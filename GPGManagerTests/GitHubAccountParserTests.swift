import Testing
@testable import GPGManager

struct GitHubAccountParserTests {
    @Test
    func parsesSingleAccount() {
        let sample = """
        github.com
          ✓ Logged in to github.com account dppeak (keyring)
          - Active account: true
          - Git operations protocol: ssh
          - Token: gho_****
          - Token scopes: 'admin:gpg_key', 'repo'
        """
        #expect(GitHubGPGService.parseAccounts(from: sample) == ["dppeak"])
    }

    @Test
    func parsesMultipleAccounts() {
        let sample = """
        github.com
          ✓ Logged in to github.com account dppeak (keyring)
          - Active account: true

          ✓ Logged in to github.com account david-vml (keyring)
          - Active account: false
        """
        let accounts = GitHubGPGService.parseAccounts(from: sample)
        #expect(accounts.sorted() == ["david-vml", "dppeak"])
    }

    @Test
    func returnsEmptyWhenNoMatchingLines() {
        let sample = "You are not logged into any GitHub hosts. Run gh auth login."
        #expect(GitHubGPGService.parseAccounts(from: sample) == [])
    }

    @Test
    func deduplicatesRepeatedAccountLines() {
        // Some gh versions repeat the account header at the top.
        let sample = """
        github.com account dppeak
          ✓ Logged in to github.com account dppeak (keyring)
        """
        #expect(GitHubGPGService.parseAccounts(from: sample) == ["dppeak"])
    }
}

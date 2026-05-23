import Foundation

struct RememberedReposStore {
    private static let storageKey = "RememberedGitRepos"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [RememberedRepo] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([RememberedRepo].self, from: data)) ?? []
    }

    func save(_ repos: [RememberedRepo]) {
        guard let data = try? JSONEncoder().encode(repos) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

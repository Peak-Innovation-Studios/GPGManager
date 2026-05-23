import Testing
@testable import GPGManager

struct HomebrewDiscoveryServiceTests {
    @Test
    func returnsAppleSiliconStandardPathWhenPresent() {
        var service = HomebrewDiscoveryService()
        service.fileIsExecutable = { $0 == "/opt/homebrew/bin/brew" }
        service.pathEnvironment = { "" }

        #expect(service.discoverBrewPath() == "/opt/homebrew/bin/brew")
    }

    @Test
    func returnsIntelStandardPathWhenAppleSiliconMissing() {
        var service = HomebrewDiscoveryService()
        service.fileIsExecutable = { $0 == "/usr/local/bin/brew" }
        service.pathEnvironment = { "" }

        #expect(service.discoverBrewPath() == "/usr/local/bin/brew")
    }

    @Test
    func fallsBackToPATHWhenStandardLocationsMissing() {
        var service = HomebrewDiscoveryService()
        service.fileIsExecutable = { $0 == "/Users/dev/.linuxbrew/bin/brew" }
        service.pathEnvironment = { "/usr/bin:/Users/dev/.linuxbrew/bin:/bin" }

        #expect(service.discoverBrewPath() == "/Users/dev/.linuxbrew/bin/brew")
    }

    @Test
    func returnsNilWhenBrewNotFoundAnywhere() {
        var service = HomebrewDiscoveryService()
        service.fileIsExecutable = { _ in false }
        service.pathEnvironment = { "/usr/bin:/bin" }

        #expect(service.discoverBrewPath() == nil)
    }

    @Test
    func prefersAppleSiliconOverIntelWhenBothPresent() {
        var service = HomebrewDiscoveryService()
        service.fileIsExecutable = { _ in true }
        service.pathEnvironment = { "" }

        #expect(service.discoverBrewPath() == "/opt/homebrew/bin/brew")
    }
}

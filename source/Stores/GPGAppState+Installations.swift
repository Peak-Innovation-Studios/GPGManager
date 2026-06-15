import AppKit
import Foundation

@MainActor
extension GPGAppState {
    func refreshInstallations() async {
        installations = await discoveryService.discover()
        if selectedGPGPath.isEmpty || !FileManager.default.isExecutableFile(atPath: selectedGPGPath) {
            selectedGPGPath = installations.first?.path ?? ""
            persistSelectedPath()
        }
    }

    func selectGPGPath(_ path: String) async {
        selectedGPGPath = path
        persistSelectedPath()
        await refreshKeys()
    }

    func chooseCustomGPGPath() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a GPG executable."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let installation = GPGInstallation(path: url.path, kind: .custom)
        if !installations.contains(where: { $0.path == installation.path }) {
            installations.append(installation)
        }
        await selectGPGPath(url.path)
    }

    private func persistSelectedPath() {
        UserDefaults.standard.set(selectedGPGPath, forKey: Self.selectedPathKey)
    }
}

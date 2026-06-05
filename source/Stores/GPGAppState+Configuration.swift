import Foundation

@MainActor
extension GPGAppState {
    func loadAgentConfig() {
        do {
            agentConfig = try agentConfigStore.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAgentConfig() {
        do {
            try agentConfigStore.save(agentConfig)
            statusMessage = "Saved \(agentConfigStore.configURL.path)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadGPGConfig() {
        do {
            gpgConfig = try gpgConfigStore.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveGPGConfig() {
        do {
            try gpgConfigStore.save(gpgConfig)
            statusMessage = "Saved \(gpgConfigStore.configURL.path)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restartAgent() async {
        guard !selectedGPGPath.isEmpty else { return }

        do {
            try await agentService.restart(gpgPath: selectedGPGPath)
            statusMessage = "Restarted gpg-agent."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import Foundation

@MainActor
extension GPGAppState {
    func refreshPinentryStatus() {
        do {
            pinentryStatus = try pinentryInstaller.currentStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func installPinentry() async {
        do {
            pinentryStatus = try await pinentryInstaller.install(gpgPath: selectedGPGPath)
            loadAgentConfig()
            statusMessage = "GPG Manager is now your system passphrase prompt."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uninstallPinentry() async {
        do {
            pinentryStatus = try await pinentryInstaller.uninstall(gpgPath: selectedGPGPath)
            loadAgentConfig()
            statusMessage = "Restored the previous passphrase prompt."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rewritePinentryToCurrentPath() async {
        do {
            pinentryStatus = try await pinentryInstaller.install(gpgPath: selectedGPGPath)
            loadAgentConfig()
            statusMessage = "Updated pinentry path to match this GPG Manager."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

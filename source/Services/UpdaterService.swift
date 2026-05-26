import Foundation
import Sparkle

/// Wraps Sparkle's updater controller so SwiftUI views can drive an update
/// check without importing Sparkle directly. The controller is started
/// immediately on init — `startingUpdater: true` enables Sparkle's background
/// schedule (governed by `SUEnableAutomaticChecks` + `SUScheduledCheckInterval`
/// from Info.plist) so a freshly-launched app can find updates without the
/// user clicking anything.
@MainActor
final class UpdaterService {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

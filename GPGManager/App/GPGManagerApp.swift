import AppKit
import SwiftUI

@main
struct GPGManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = GPGAppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    await appState.bootstrap()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("GPG") {
                Button("Refresh") {
                    Task { await appState.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Restart Agent") {
                    Task { await appState.restartAgent() }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        Window("Public Keys", id: "public-keys") {
            PublicKeysView()
                .environment(appState)
                .frame(minWidth: 880, minHeight: 540)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

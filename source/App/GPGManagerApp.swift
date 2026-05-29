import AppKit
import SwiftUI

@main
struct GPGManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = GPGAppState()
    private let updater = UpdaterService()

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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
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
            HelpCommands()
        }

        Window("Public Keys", id: "public-keys") {
            PublicKeysView()
                .environment(appState)
                .frame(minWidth: 880, minHeight: 540)
        }
        .windowResizability(.contentSize)

        Window("GPG Manager Help", id: "help") {
            HelpView()
                .frame(minWidth: 780, minHeight: 540)
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
    }
}

private struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("GPG Manager Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: [.command])

            Divider()

            ForEach(HelpTopic.Category.allCases, id: \.self) { category in
                let topics = HelpContent.topics(in: category)
                if !topics.isEmpty {
                    Section(category.rawValue) {
                        ForEach(topics) { topic in
                            Button(topic.title) {
                                UserDefaults.standard.set(topic.id, forKey: "help.selectedTopic")
                                openWindow(id: "help")
                            }
                        }
                    }
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

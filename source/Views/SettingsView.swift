import SwiftUI

struct SettingsView: View {
    enum SettingsTab: String, Hashable, CaseIterable {
        case passphrase = "Passphrase"
        case keyServer = "Key Server"
        case about = "About"

        var systemImage: String {
            switch self {
            case .passphrase: "lock"
            case .keyServer:  "network"
            case .about:      "info.circle"
            }
        }

        /// Used as the initial frame height before a live measurement arrives.
        var fallbackHeight: CGFloat {
            switch self {
            case .passphrase: 520
            case .keyServer:  420
            case .about:      460
            }
        }
    }

    @Environment(GPGAppState.self) private var state
    @State private var selection: SettingsTab = .passphrase
    @State private var measuredHeights: [SettingsTab: CGFloat] = [:]

    private var currentHeight: CGFloat {
        measuredHeights[selection] ?? selection.fallbackHeight
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(SettingsTab.passphrase.rawValue, systemImage: SettingsTab.passphrase.systemImage, value: .passphrase) {
                PassphraseSettingsTab().measuringHeight(for: .passphrase, into: $measuredHeights)
            }
            Tab(SettingsTab.keyServer.rawValue, systemImage: SettingsTab.keyServer.systemImage, value: .keyServer) {
                KeyServerSettingsTab().measuringHeight(for: .keyServer, into: $measuredHeights)
            }
            Tab(SettingsTab.about.rawValue, systemImage: SettingsTab.about.systemImage, value: .about) {
                AboutSettingsTab().measuringHeight(for: .about, into: $measuredHeights)
            }
        }
        .frame(width: 620, height: currentHeight)
        .animation(.easeInOut(duration: 0.18), value: currentHeight)
        .onChange(of: state.gpgConfig) { _, _ in
            state.saveGPGConfig()
            state.loadGPGConfig()
        }
        .onChange(of: state.agentConfig) { _, _ in
            state.saveAgentConfig()
            state.loadAgentConfig()
        }
    }
}

private extension View {
    func measuringHeight(
        for tab: SettingsView.SettingsTab,
        into measurements: Binding<[SettingsView.SettingsTab: CGFloat]>
    ) -> some View {
        self
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                measurements.wrappedValue[tab] = newHeight
            }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environment(GPGAppState.preview)
}
#endif

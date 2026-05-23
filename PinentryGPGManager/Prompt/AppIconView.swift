import AppKit
import SwiftUI

/// Loads and displays the parent GPGManager.app icon.
/// Falls back to an SF Symbol when the helper isn't running from inside an app bundle.
struct AppIconView: View {
    var size: CGFloat = 56
    var fallbackSystemImage: String = "lock.shield"

    var body: some View {
        if let icon = AppIconView.cachedIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSystemImage)
                .font(.system(size: size * 0.55))
                .foregroundStyle(.tint)
                .frame(width: size, height: size)
        }
    }

    private static let cachedIcon: NSImage? = loadIcon()

    private static func loadIcon() -> NSImage? {
        guard let appBundle = locateParentAppBundle() else { return nil }

        // Prefer reading the .icns directly — avoids the macOS icon services cache,
        // which can return a stale image after the bundle's icon was replaced.
        if let icnsURL = findFirstIcns(in: appBundle),
           let image = NSImage(contentsOf: icnsURL) {
            return image
        }

        return NSWorkspace.shared.icon(forFile: appBundle.path)
    }

    private static func locateParentAppBundle() -> URL? {
        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
        var url = URL(fileURLWithPath: executablePath)
        while url.pathExtension != "app" {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
        return url
    }

    private static func findFirstIcns(in appBundle: URL) -> URL? {
        let resources = appBundle.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let contents = try? FileManager.default.contentsOfDirectory(
            at: resources,
            includingPropertiesForKeys: nil
        )
        return contents?.first { $0.pathExtension == "icns" }
    }
}

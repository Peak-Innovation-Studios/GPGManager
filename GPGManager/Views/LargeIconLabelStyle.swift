import SwiftUI

/// A `LabelStyle` that scales the icon up while leaving the text at its natural size.
/// Used in the sidebar and GroupBox section headers to give icons more visual weight.
struct LargeIconLabelStyle: LabelStyle {
    var iconSize: CGFloat = 18
    var spacing: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
                .font(.system(size: iconSize, weight: .regular))
                .frame(width: iconSize + 4, alignment: .center)
            configuration.title
        }
    }
}

extension LabelStyle where Self == LargeIconLabelStyle {
    /// Sidebar / card-header presentation: 18pt icon, default text size.
    static var largeIcon: LargeIconLabelStyle { LargeIconLabelStyle() }

    static func largeIcon(size: CGFloat) -> LargeIconLabelStyle {
        LargeIconLabelStyle(iconSize: size)
    }
}

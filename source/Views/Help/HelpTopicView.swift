import SwiftUI

struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                ForEach(Array(topic.sections.enumerated()), id: \.offset) { _, section in
                    HelpSectionView(section: section)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: topic.systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .frame(width: 36, alignment: .leading)
                Text(topic.title)
                    .font(.largeTitle)
                    .bold()
            }
            Text(topic.summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HelpSectionView: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let heading = section.heading {
                Text(heading)
                    .font(.title2)
                    .bold()
                    .padding(.top, 4)
            }
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                HelpBlockView(block: block)
            }
        }
    }
}

#if DEBUG
#Preview {
    HelpTopicView(topic: .gettingStarted)
        .frame(width: 720, height: 700)
}
#endif

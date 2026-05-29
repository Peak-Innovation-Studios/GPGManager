import SwiftUI

struct HelpView: View {
    @AppStorage("help.selectedTopic") private var storedSelection: String = HelpTopic.welcome.id

    private var selection: Binding<String?> {
        Binding(
            get: { storedSelection },
            set: { storedSelection = $0 ?? HelpTopic.welcome.id }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            if let topic = HelpContent.topic(id: storedSelection) {
                HelpTopicView(topic: topic)
                    .id(storedSelection)
            } else {
                ContentUnavailableView(
                    "Pick a topic",
                    systemImage: "questionmark.circle",
                    description: Text("Choose a topic from the sidebar to read the documentation.")
                )
            }
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(HelpTopic.Category.allCases, id: \.self) { category in
                let topics = HelpContent.topics(in: category)
                if !topics.isEmpty {
                    Section(category.rawValue) {
                        ForEach(topics) { topic in
                            Label(topic.title, systemImage: topic.systemImage)
                                .tag(topic.id as String?)
                        }
                    }
                }
            }
        }
        .navigationTitle("Help")
    }
}

#if DEBUG
#Preview {
    HelpView()
        .frame(width: 880, height: 600)
}
#endif

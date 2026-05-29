# Prompt — In-app help system + polished About

Build a native, in-app help system and refine the About window. Goal: a sidebar of categorized topics, a content pane that supports paragraphs / bullets / steps / code / callouts / key-value pairs, and Help-menu items that deep-link to specific topics. Same quality bar as a well-written README, but rendered natively.

## Step 0 — Inventory first, write second

**Before writing any content**, read the codebase and produce a feature inventory. For each major surface (sidebar tab, sheet, settings pane, menu command), list:

- What it does in one sentence
- Every field, button, or toggle on it
- Non-obvious behavior (defaults, side effects, what config it writes to disk, etc.)

Confirm the inventory with me before authoring content. Don't guess features from training data — read the actual views and models.

## Architecture

Split data from rendering. One topic per file in extensions, so each file stays ≤ 250 lines.

```swift
// Models/HelpTopic.swift
struct HelpTopic: Identifiable, Hashable {
    enum Category: String, CaseIterable, Hashable {
        case gettingStarted = "Getting Started"
        case features       = "Features"
        case configuration  = "Configuration"
        case reference      = "Reference"
    }
    let id: String                // slug, used by Help-menu deep links
    let title: String
    let summary: String           // one line, shown under the title
    let systemImage: String       // SF Symbol
    let category: Category
    let sections: [HelpSection]
}

struct HelpSection: Hashable {
    let heading: String?
    let blocks: [HelpBlock]
    init(_ blocks: [HelpBlock]) { self.heading = nil; self.blocks = blocks }
    init(_ heading: String, _ blocks: [HelpBlock]) { self.heading = heading; self.blocks = blocks }
}

enum HelpBlock: Hashable {
    case paragraph(String)                       // Markdown via LocalizedStringKey
    case bullets([String])
    case steps([String])                         // numbered
    case code(String, caption: String? = nil)    // monospaced, with copy button
    case tip(String)                             // yellow callout, lightbulb
    case note(String)                            // accent callout, info.circle
    case warning(String)                         // orange callout, exclamationmark.triangle
    case keyValue([(String, String)])            // two-column rows; value is Markdown
}

enum HelpContent {
    static var allTopics: [HelpTopic] { /* assembled from extensions */ }
    static func topic(id: String) -> HelpTopic? { allTopics.first { $0.id == id } }
    static func topics(in c: HelpTopic.Category) -> [HelpTopic] { allTopics.filter { $0.category == c } }
}
```

**Important Swift gotcha:** the two `HelpSection` initializers must be separate overloads, not one with `String? = nil` default. The compiler can't bind a leading `[HelpBlock]` array literal to the second parameter when the first parameter has a default — it tries to coerce the array into the optional string and fails.

Each topic lives in its own file:

```swift
// Models/HelpTopic+GettingStarted.swift
extension HelpTopic {
    static let gettingStarted = HelpTopic(
        id: "getting-started",
        title: "Getting Started",
        summary: "From a fresh install to <real outcome>.",
        systemImage: "flag.checkered",
        category: .gettingStarted,
        sections: [
            HelpSection([ .paragraph("...") ]),
            HelpSection("1. Install", [ .code("brew install ...", caption: "Run in Terminal") ]),
            HelpSection("2. Configure", [ .steps(["...", "..."]) ]),
            // ...
        ]
    )
}
```

## Rendering

Three views — each under ~250 lines:

- **HelpView** — `NavigationSplitView` with a sidebar (`List` selection, sections per `Category`) and a detail showing the selected `HelpTopicView`. Selection persists via `@AppStorage("help.selectedTopic")` so menu deep links work.
- **HelpTopicView** — header (icon + title + summary) and a `VStack` of `HelpSectionView`s. Max content width ~720pt for readable line length.
- **HelpBlockView** — `switch` on `HelpBlock`. For paragraphs and bullets/steps/key-values, render with `Text(LocalizedStringKey(text))` so Markdown bold/italic/`code` works. Code blocks get a copy button (`NSPasteboard.general.setString`). Callouts are a tinted rounded rect with an SF Symbol and a label ("Tip" / "Note" / "Heads up").

## Wiring

```swift
// App body — add a Window scene + commands
Window("AppName Help", id: "help") {
    HelpView().frame(minWidth: 780, minHeight: 540)
}

.commands {
    // ... existing commands
    HelpCommands()
}

private struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("AppName Help") { openWindow(id: "help") }
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
```

## Content style guide

Voice: explain it to a smart friend. Concrete, specific, never vague.

- **Lead with the result, not the mechanism.** "Click Add to GitHub to register the key" > "The Add to GitHub button invokes a method that…"
- **Use real code, real paths, real commands.** Not `<your-thing-here>` placeholders.
- **Bold the verbs and UI labels** (`**Apply**`, `**Sign commits by default**`) — they jump out when skimming.
- **Backtick exact config keys and CLI names** (`gpg.program`, `gh auth refresh`) — the reader copies these.
- **Every feature gets a worked example.** "Sign only one work repo with a different key. Target = Add Repository… and pick the folder. Choose the work key. Turn on Sign commits. Apply."
- **Inline rationales.** When you mention a setting, say *why* you'd want it on or off — not just *what* it does.

Topic checklist (cover all that exist in the codebase):

1. **Welcome** — what the app is, what it can do, where things live.
2. **Getting Started** — numbered walkthrough from install to first successful use.
3. **One topic per major feature** — every tab, every sheet, every workflow.
4. **Configuration topics** — one per Settings pane.
5. **Menus & Shortcuts** — table of every keyboard shortcut and menu command.
6. **Troubleshooting** — one section per common failure mode, with the diagnostic and the fix. Cover the issues that come up most often in support.

## About window polish

Improve the existing About surface (whether it's a Settings tab or a standalone About window). Pattern that worked:

- Hero: 112pt app icon with a soft drop shadow.
- Title in `.system(size: 26, weight: .semibold)`. One-line tagline under it.
- "Version X · Build N" pill — capsule background, `.quaternary` fill, monospaced digits, `textSelection(.enabled)`. Small copy-to-clipboard button next to it that copies version + runtime info.
- Row of three bordered link buttons (Website / Repo / Issues) using `Link` + `Label(_:systemImage:)`. `controlSize(.small)`.
- A GroupBox showing runtime/environment info that's actually useful for bug reports.
- Footer: copyright + any third-party license disclaimer in `.caption2`/`.tertiary`.

## Acceptance criteria

- ⌘? opens the Help window. Sidebar groups topics by Category.
- Every Help-menu sub-item jumps directly to that topic.
- Code blocks have a copy button that works.
- Paragraphs render Markdown bold/italic/`code` correctly.
- Every feature visible in the UI has a dedicated topic or a clearly-named section.
- Troubleshooting topic covers the top 5+ failure modes with concrete fixes.
- About window passes the "would I be proud to ship this" test.
- Project builds clean. Light + Dark previews look right.

---

Adapt the SF Symbols, category names, and link URLs to the target project. Everything else should port directly.

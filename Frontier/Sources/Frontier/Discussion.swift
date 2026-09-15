import SwiftUI
import LocalSupport

extension Model {
    var discussionID: String { activeMaterial?.id ?? current?.id ?? "general" }
    func discussion(for id: String) -> AIConversation {
        if let existing = discussions[id] { return existing }
        let chat = AIConversation(app: "Frontier", id: id); discussions[id] = chat; return chat
    }
    func explainArticlePassage(_ text: String, material: LibraryMaterial) {
        showingDiscussion = true
        let chat = discussion(for: material.id)
        let question = "Explain this selected passage clearly, defining unfamiliar terms.\n\n" + text
        let context = "Material: \(material.title)\nSelected formatted passage:\n\(text)\n\nNearby formatted text:\n" + (articleContexts[material.id] ?? "No nearby text is available.") + "\nFigures are not included. State limits rather than guessing missing evidence."
        chat.draft = question
        Task { await chat.send(question, source: { context }, settings: { try AISettings.load() }) }
    }

    var discussionContext: String {
        var source = "Mode: reading companion. Help me understand the source and explain notation. Give a direct explanation; do not quiz me unless I ask.\n"
        if let item = activeMaterial {
            source += "Material: \(item.title)\n"
            // Keep the current section, rather than silently always supplying the start of a book.
            if [.source, .compare].contains(readingMode), let reader = pdfReader(for: item) {
                source += reader.discussionExcerpt() + "\n"
            } else if readingMode == .learn, let context = articleContexts[item.id] {
                source += "Formatted text around the current reading position (figures are not included):\n" + context + "\n"
            } else if readingMode == .learn, let reader = pdfReader(for: item) {
                source += reader.discussionExcerpt() + "\n"
            } else if !item.sections.isEmpty {
                let section = item.sections[min(max(0, item.sectionIndex), item.sections.count - 1)]
                source += "Extracted section: \(section.title) (may lose PDF math/figures; not the full source):\n\(section.text.prefix(60000))\n"
            }
        }
        if let concept = current, readingMode == .walkthrough || activeMaterial == nil { source += "Learning concept: \(concept.title)\n\(concept.relevance + "\n" + concept.body)\n" }
        return source
    }
}

struct FrontierDiscussion: View {
    @ObservedObject var model: Model
    let configure: () -> Void
    var body: some View {
        DiscussionPanel(conversation: model.discussion(for: model.discussionID), title: "Think it through",
            scope: "Context: nearby reading text or the current walkthrough; in Original PDF, the current page and its neighbors. Figures are not sent. Selected passages are included when explained.",
            source: { model.discussionContext }, settings: { try AISettings.load() }, configure: configure,
            close: { model.showingDiscussion = false }) { ConceptPreview(markdown: $0) }
            .background(LibraryTheme.paper)
    }
}

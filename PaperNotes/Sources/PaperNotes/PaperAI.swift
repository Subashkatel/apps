import LocalSupport
import Foundation
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

enum PaperAI {
    static var settingsURL: URL { LocalConfig.dataDirectory("Paper Notes").appendingPathComponent("ai-settings.json") }
    static func load() throws -> AISettings {
        if FileManager.default.fileExists(atPath: settingsURL.path) { return try AISettings.load(from: settingsURL) }
        return try AISettings.load() // Start with Frontier's configured provider; save independently thereafter.
    }
    static func context(_ paper: Paper) -> String {
        let excerpt = paper.resolvedPDF.flatMap { PDFDocument(url: $0) }.map { document in
            (0..<min(document.pageCount, 20)).map { "[PDF page \($0 + 1)]\n" + (document.page(at: $0)?.string ?? "") }.joined(separator: "\n\n")
        } ?? "No original PDF is attached. Do not infer what the paper says from the title."
        return """
        Mode: critical review. Help the reader assess claims, evidence, assumptions, limitations and connections.
        Do not write over their judgments. An uncertain understanding is something to explore, not a reason to penalize them.
        Paper: \(paper.title)
        Reader's current notes (not source evidence):\n\(paper.body.prefix(24000))
        PDF excerpt (first 20 pages, up to 60000 characters; text extraction may lose math/figures):\n\(excerpt.prefix(60000))
        """
    }
}

extension AppModel {
    func discussion(for id: String) -> AIConversation {
        if let value = conversations[id] { return value }
        let value = AIConversation(app: "Paper Notes", id: id); conversations[id] = value; return value
    }

    func attachPDF(_ paper: Paper) {
        guard flushDraft() else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let path = Library.adopt(url, for: paper.arxivID) else { status = "Could not attach this PDF. Check that it is a readable PDF."; return }
        guard var updated = Library.shared.paper(withID: paper.arxivID) else { return }
        updated.pdfPath = path
        updated.refs = PDFRefs.references(in: URL(fileURLWithPath: path), excluding: updated.arxivID)
        guard Library.shared.save(updated) != nil else { return }
        refresh(); select(updated.arxivID); status = "Original PDF attached."
    }
}

struct PaperDiscussion: View {
    @Bindable var model: AppModel
    let paper: Paper
    let close: () -> Void
    let configure: () -> Void
    @StateObject private var conversation: AIConversation
    init(model: AppModel, paper: Paper, close: @escaping () -> Void, configure: @escaping () -> Void) {
        self.model = model; self.paper = paper; self.close = close; self.configure = configure
        _conversation = StateObject(wrappedValue: model.discussion(for: paper.arxivID))
    }
    var body: some View {
        DiscussionPanel(conversation: conversation, title: "Discuss this paper",
            scope: "Context: this review + PDF excerpt (up to 20 pages). Answers may need checking against the original.",
            source: { let snapshot = model.draft ?? paper; return await Task.detached { PaperAI.context(snapshot) }.value },
            settings: { try PaperAI.load() }, configure: configure, close: close,
            saveAnswer: { answer in
                model.draft?.body += "\n\n## AI discussion · saved excerpt\n\n" + answer + "\n"
            }) { MarkdownPreview(markdown: $0) }
    }
}

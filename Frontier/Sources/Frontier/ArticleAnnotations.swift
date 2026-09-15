import AppKit
import PDFKit
import SwiftUI

/// Whitespace-insensitive matching with original UTF-16 offsets for PDFKit.
/// Ambiguous or missing passages are deliberately not assigned to a page.
struct PassageTextIndex: Sendable {
    let text: String
    let offsets: [Int]
    init(_ source: String) {
        var normalized = "", locations: [Int] = [], offset = 0
        for scalar in source.unicodeScalars {
            let length = String(scalar).utf16.count
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) && scalar.value != 0x00AD {
                let value = String(scalar).lowercased()
                normalized += value; locations += Array(repeating: offset, count: value.utf16.count)
            }
            offset += length
        }
        text = normalized; offsets = locations + [offset]
    }
    func ranges(matching passage: String) -> [NSRange] {
        let text = text as NSString, needle = PassageTextIndex(passage).text as NSString
        guard needle.length >= 12 else { return [] }
        var cursor = 0, result: [NSRange] = []
        while cursor < text.length {
            let match = text.range(of: needle as String, range: NSRange(location: cursor, length: text.length-cursor))
            guard match.location != NSNotFound else { break }
            result.append(NSRange(location: offsets[match.location], length: offsets[NSMaxRange(match)]-offsets[match.location]))
            if result.count > 1 { break }
            cursor = match.location + 1
        }
        return result
    }
}

extension SourcePDF {
    func selectArticlePassage(_ text: String) async throws {
        guard text.count <= 24000 else { throw FrontierError("Select a shorter passage to annotate.") }
        if articleIndexTask == nil {
            let url = original
            articleIndexTask = Task.detached(priority: .userInitiated) {
                guard let pdf = PDFDocument(url: url) else { return [] }
                return (0..<pdf.pageCount).map { PassageTextIndex(pdf.page(at: $0)?.string ?? "") }
            }
        }
        let pages = await articleIndexTask!.value
        try Task.checkCancellation()
        let matches = await Task.detached(priority: .userInitiated) {
            var found: [(Int, NSRange)] = []
            for (page, index) in pages.enumerated() {
                found += index.ranges(matching: text).map { (page, $0) }
                if found.count > 1 { break }
            }
            return found
        }.value
        try Task.checkCancellation()
        guard matches.count == 1, let match = matches.first,
              let page = document?.page(at: match.0), let selection = page.selection(for: match.1),
              PassageTextIndex(selection.string ?? "").text == PassageTextIndex(text).text else {
            throw FrontierError("This passage could not be matched uniquely to the PDF. Select a longer passage, or locate it in Original PDF to annotate it. No note was attached.")
        }
        go(to: match.0 + 1)
        view.setCurrentSelection(selection, animate: false)
    }
    var articleMarks: [[String: Any]] {
        annotations.map { mark in
            let color = mark.color.usingColorSpace(.deviceRGB) ?? .yellow
            return ["id": mark.stableID, "quote": quote(for: mark),
                    "color": "rgba(\(Int(color.redComponent*255)),\(Int(color.greenComponent*255)),\(Int(color.blueComponent*255)),0.25)"]
        }
    }
}

struct AnnotatedArticleReader: View {
    let article: FormattedArticle
    let positionURL: URL
    @ObservedObject var source: SourcePDF
    let openOriginal: () -> Void
    let explain: (String) -> Void
    var contextChanged: (String) -> Void = { _ in }
    @State private var selection = ""
    private var showingNotes: Bool { get { source.showingNotes } nonmutating set { source.showingNotes = newValue } }
    @State private var matching = false
    @State private var matchError: String?
    @State private var revealID: String?
    @State private var revealRequest = 0
    @State private var annotationTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !selection.isEmpty {
                    Menu { ForEach(HighlightColor.allCases, id: \.self) { color in
                        Button(color.rawValue) { source.highlightColor = color }
                    } } label: { Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: source.highlightColor.color)) }
                        .menuIndicator(.hidden).fixedSize().help("Highlight color")
                    Button("Highlight") { annotate(note: false) }.accessibilityIdentifier("article-highlight")
                    Button("Add note") { annotate(note: true) }.accessibilityIdentifier("article-add-note")
                    Button("Explain") { explain(selection) }.accessibilityIdentifier("article-explain")
                } else { Text("Select a passage to highlight, note, or explain.").font(.system(size: 11)).foregroundStyle(LibraryTheme.muted) }
                if matching { ProgressView().controlSize(.small) }
                Spacer(minLength: 4)
                if source.canUndo { Button("Undo") { source.undo() } }
                Button("Notes \(source.annotations.count)") { showingNotes.toggle() }.accessibilityIdentifier("article-toggle-notes")
            }.buttonStyle(.borderless).font(.system(size: 12)).padding(.horizontal, 18).padding(.vertical, 10).disabled(matching)
            HStack(spacing: 0) {
                ArticlePane(article: article, positionURL: positionURL, marks: source.articleMarks, revealID: revealID, revealRequest: revealRequest, revealUnavailable: { openOriginal() },
                            selectionChanged: { selection = $0 }, noteClicked: { id in
                    guard let mark = source.annotations.first(where: { $0.stableID == id }) else { return }
                    source.focusedAnnotation = mark; showingNotes = true
                }, contextChanged: contextChanged).frame(maxWidth: .infinity, maxHeight: .infinity)
                if showingNotes {
                    PDFNotesPanel(source: source, showing: $source.showingNotes, reveal: { mark in
                        source.reveal(mark); revealID = mark.stableID; revealRequest += 1
                    })
                }
            }
            if let message = matchError ?? source.draftError ?? source.error {
                HStack { Text(message).font(.caption); Spacer(); Button("Original PDF") { openOriginal() }; if matchError != nil { Button("Dismiss") { matchError = nil } }
                    else { Button("Retry save") { source.saveNoteDraft(); Task { _ = await source.flushInBackground() } } } }.padding(12)
            }
        }.background(LibraryTheme.paper)
        .onAppear { if source.noteDraft != nil { showingNotes = true } }
        .onChange(of: source.focusRequest) { _, _ in if source.focusedAnnotation != nil { showingNotes = true } }
        .onDisappear { annotationTask?.cancel(); source.saveWithoutBlocking() }
    }
    private func annotate(note: Bool) {
        if note, source.noteDraft != nil { showingNotes = true; return }
        let passage = selection
        matching = true; matchError = nil
        annotationTask = Task {
            defer { matching = false }
            do {
                try await source.selectArticlePassage(passage)
                guard source.document?.allowsCommenting == true else { throw FrontierError("This PDF does not allow annotations.") }
                source.highlight()
                if note, let mark = source.focusedAnnotation { source.beginNote(mark) }
                showingNotes = true
            } catch is CancellationError {} catch { matchError = error.localizedDescription }
        }
    }
}

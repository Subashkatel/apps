import LocalSupport
import AppKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// The original remains immutable. Standard PDF annotations are saved in a
/// separate, portable copy beside it, with atomic replacement on each edit.
@MainActor final class SourcePDF: ObservableObject {
    let view = MarginPDFView()
    var articleIndexTask: Task<[PassageTextIndex], Never>?
    let original: URL
    let annotated: URL
    @Published var error: String?
    var notesOpened: (() -> Void)?
    @Published var showingNotes = false { didSet { if showingNotes && !oldValue { notesOpened?() } } }
    @Published var hasSelection = false
    @Published var pageNumber = 1
    @Published var revision = 0
    @Published var dirty = false
    @Published var focusRequest = 0
    @Published var focusedAnnotation: PDFAnnotation? { didSet { focusRequest += 1 } }
    @Published var highlightColor = HighlightColor(rawValue: UserDefaults.standard.string(forKey: "frontier.highlight.color") ?? "") ?? .yellow {
        didSet {
            if ProcessInfo.processInfo.environment["LOCAL_APPS_TESTING"] != "1" {
                UserDefaults.standard.set(highlightColor.rawValue, forKey: "frontier.highlight.color")
            }
        }
    }
    struct NoteDraft: Codable, Equatable {
        var text: String
        var annotationID: String?
        var page: Int
        var bounds: CGRect?
        var quote: String
        var creating: Bool = false
    }
    @Published var noteDraft: NoteDraft? { didSet { saveNoteDraft() } }
    @Published var draftError: String?
    @Published var savingNote = false
    private var draftUnreadable = false
    private var draftURL: URL { annotated.appendingPathExtension("draft.json") }
    func saveNoteDraft() {
        guard !draftUnreadable else { return }
        do {
            if let noteDraft { try JSONEncoder().encode(noteDraft).write(to: draftURL, options: .atomic) }
            else if FileManager.default.fileExists(atPath: draftURL.path) { try FileManager.default.removeItem(at: draftURL) }
            draftError = nil
        } catch { draftError = "Your note draft is still open but could not be saved: " + error.localizedDescription }
    }
    func beginNote(_ annotation: PDFAnnotation? = nil) {
        // Reopen an unfinished thought instead of silently replacing it.
        guard noteDraft == nil else { return }
        if let annotation = annotation ?? noteTarget, let page = annotation.page, let document {
            noteDraft = NoteDraft(text: noteText(for: annotation), annotationID: persistentID(for: annotation),
                                  page: document.index(for: page), bounds: annotation.bounds, quote: quote(for: annotation))
        } else if let anchor = noteAnchor(), let document {
            noteDraft = NoteDraft(text: "", page: document.index(for: anchor.page), bounds: anchor.bounds, quote: anchor.quote)
        }
    }
    @discardableResult func keepNoteDraft() -> Bool {
        guard let draft = noteDraft, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let id = draft.annotationID {
            if let annotation = annotations.first(where: { $0.groupID == id }) {
                edit(annotation, text: draft.text)
            } else if draft.creating, let page = document?.page(at: draft.page),
                      addNote(draft.text, at: NoteAnchor(page: page, bounds: draft.bounds, quote: draft.quote)) {
                noteDraft?.annotationID = focusedAnnotation?.groupID
            } else {
                error = "This annotation was removed. Your draft is kept; copy it or cancel it before starting another note."
                return false
            }
        } else {
            guard let page = document?.page(at: draft.page),
                  addNote(draft.text, at: NoteAnchor(page: page, bounds: draft.bounds, quote: draft.quote)) else { return false }
        }
        if draft.annotationID == nil, let annotation = focusedAnnotation {
            noteDraft?.creating = true
            noteDraft?.annotationID = annotation.groupID
        }
        // Keep a recovery copy until the annotation write has succeeded.
        return true
    }
    func commitNoteDraft() async -> Bool {
        guard !savingNote, keepNoteDraft() else { return false }
        let submitted = noteDraft
        savingNote = true; defer { savingNote = false }
        guard await flushInBackground() else { return false }
        if noteDraft == submitted { noteDraft = nil }
        return true
    }
    private var pendingSave: Task<Void, Never>?
    private var touchedPages = Set<Int>()
    private let saveQueue = DispatchQueue(label: "frontier.pdf-save", qos: .utility)

    @Published var sendingToReview = false
    func discussionExcerpt() -> String {
        guard let document, document.pageCount > 0 else { return "No readable PDF text is available. Do not infer its contents." }
        let index = min(max(pageNumber - 1, 0), document.pageCount - 1)
        let pages = (max(0, index - 1)...min(document.pageCount - 1, index + 1))
        let excerpt = pages.map { i in
            "[PDF page \(i + 1)\(i == index ? " — current page" : "")]\n" + String((document.page(at: i)?.string ?? "").prefix(20000))
        }.joined(separator: "\n\n")
        return "PDF excerpt around current page \(index + 1). Text extraction may lose math/figures; do not claim to see them.\n" + excerpt
    }

    var sendToReview: ((PDFAnnotation) -> Void)?
    var explainSelection: ((String, Int) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var undoEdits: [() -> Void] = []
    private var annotationCache: [PDFAnnotation] = []
    private var cachedRevision = -1
    private var legacyQuotes: [String: String] = [:]
    private var initialPage: Int?
    var document: PDFDocument? { view.document }
    var pageCount: Int { document?.pageCount ?? 0 }
    var canUndo: Bool { !undoEdits.isEmpty }
    var annotations: [PDFAnnotation] {
        guard let document else { return [] }
        if cachedRevision != revision {
            var result: [PDFAnnotation] = []
            for index in 0..<document.pageCount {
                for annotation in document.page(at: index)?.annotations ?? [] {
                    if annotation.type == "Highlight" || annotation.type == "Text" { result.append(annotation) }
                }
            }
            var seen = Set<String>()
            annotationCache = result.filter { annotation in
                guard let id = annotation.groupID else { return true }
                return seen.insert(id).inserted
            }; cachedRevision = revision
        }
        return annotationCache
    }

    init(original: URL, annotated: URL) {
        self.original = original; self.annotated = annotated
        view.annotationClicked = { [weak self] annotation in self?.focusedAnnotation = annotation }

        initialPage = (try? Data(contentsOf: annotated.appendingPathExtension("position.json"))).flatMap { try? JSONDecoder().decode(Int.self, from: $0) }
        let source = FileManager.default.fileExists(atPath: annotated.path) ? annotated : original
        // Retain PDFKit's URL-backed document for efficient page loading.
        view.document = PDFDocument(url: source)
        view.autoScales = true; view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 28/255, green: 30/255, blue: 27/255, alpha: 1) : NSColor(srgbRed: 0.9, green: 0.9, blue: 0.87, alpha: 1)
        }
        if FileManager.default.fileExists(atPath: draftURL.path) {
            do { noteDraft = try JSONDecoder().decode(NoteDraft.self, from: Data(contentsOf: draftURL)) }
            catch { draftUnreadable = true; draftError = "Could not read the saved note draft. The draft file has been preserved." }
        }
        if view.document == nil { error = "This PDF could not be opened." }
        if view.document?.isLocked == true { error = "This PDF is password protected. Unlock a copy before attaching it." }
        observers.append(NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hasSelection = !(self?.view.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let page = self.view.currentPage else { return }
                self.pageNumber = (self.document?.index(for: page) ?? 0) + 1
                try? JSONEncoder().encode(self.pageNumber).write(to: self.positionURL, options: .atomic)
            }
        })
    }
    var positionURL: URL { annotated.appendingPathExtension("position.json") }
    func restorePosition(fallback: Int? = nil) {
        if let number = initialPage ?? fallback { go(to: number) }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func highlight(note: String = "") {
        guard let selection = view.currentSelection, document?.allowsCommenting == true else {
            error = "Select text first. The PDF must allow annotations."; return
        }
        var edits: [(PDFPage, PDFAnnotation, Bool)] = []
        let groupID = UUID().uuidString
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty, !bounds.isInfinite else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = highlightColor.color.withAlphaComponent(0.45)
                annotation.contents = note.isEmpty ? selection.string : note
                annotation.setValue(selection.string ?? "", forAnnotationKey: PDFMark.quoteKey)
                annotation.setValue(groupID, forAnnotationKey: PDFMark.idKey)
                touch(page)
                page.addAnnotation(annotation)
                edits.append((page, annotation, true))
            }
        }
        guard !edits.isEmpty else { error = "The selection has no text to highlight."; return }
        undoEdits.append { for (page, annotation, _) in edits { page.removeAnnotation(annotation) } }; view.clearSelection(); focusedAnnotation = edits.first?.1; changed()
    }
    struct NoteAnchor {
        let page: PDFPage
        let bounds: CGRect?
        let quote: String
    }
    // Once highlighting consumes the selection, Add note edits that passage's mark.
    var noteTarget: PDFAnnotation? {
        guard view.currentSelection?.string?.isEmpty != false,
              let mark = focusedAnnotation, mark.page === view.currentPage,
              mark.page?.annotations.contains(where: { $0 === mark }) == true else { return nil }
        return mark
    }
    func noteAnchor() -> NoteAnchor? {
        guard let page = view.currentSelection?.pages.first ?? view.currentPage else { return nil }
        return NoteAnchor(page: page, bounds: view.currentSelection?.bounds(for: page), quote: view.currentSelection?.string ?? "")
    }
    func quote(for annotation: PDFAnnotation) -> String {
        if let quote = annotation.value(forAnnotationKey: PDFMark.quoteKey) as? String { return quote }
        guard annotation.type == "Highlight" else { return "" }
        if let cached = legacyQuotes[annotation.stableID] { return cached }
        let quote = group(annotation).compactMap { page, mark in page.selection(for: mark.bounds)?.string }.joined(separator: "\n")
        legacyQuotes[annotation.stableID] = quote
        return quote
    }
    func noteText(for annotation: PDFAnnotation) -> String {
        let content = annotation.contents ?? ""
        func normalized(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return annotation.type == "Highlight" && normalized(content) == normalized(quote(for: annotation)) ? "" : content
    }
    @discardableResult func addNote(_ text: String, at anchor: NoteAnchor? = nil) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let anchor = anchor ?? noteAnchor(),
              document?.allowsCommenting == true, anchor.page.document === document else { error = "This PDF does not allow adding notes."; return false }
        let page = anchor.page
        let selected = anchor.bounds
        let pageBounds = page.bounds(for: .cropBox)
        let rect = CGRect(x: min(max(selected?.maxX ?? pageBounds.minX + 20, pageBounds.minX), pageBounds.maxX - 24),
                          y: min(max(selected?.maxY ?? pageBounds.maxY - 44, pageBounds.minY), pageBounds.maxY - 24), width: 22, height: 22)
        let annotation = PDFAnnotation(bounds: rect, forType: .text, withProperties: nil)
        annotation.color = highlightColor.color; annotation.contents = text
        annotation.setValue(anchor.quote, forAnnotationKey: PDFMark.quoteKey)
        annotation.setValue(UUID().uuidString, forAnnotationKey: PDFMark.idKey)
        touch(page)
        page.addAnnotation(annotation); focusedAnnotation = annotation; undoEdits.append { page.removeAnnotation(annotation) }; changed()
        return true
    }
    private func touch(_ page: PDFPage) { if let document { touchedPages.insert(document.index(for: page)) } }
    private func group(_ annotation: PDFAnnotation) -> [(PDFPage, PDFAnnotation)] {
        guard let page = annotation.page else { return [] }
        guard let id = annotation.groupID, let document else { return [(page, annotation)] }
        // A multiline highlight is one action, even when PDFKit stores one mark per line.
        return (0..<document.pageCount).flatMap { index -> [(PDFPage, PDFAnnotation)] in
            guard let page = document.page(at: index) else { return [] }
            return page.annotations.filter { $0.groupID == id }.map { (page, $0) }
        }
    }
    func edit(_ annotation: PDFAnnotation, text: String) {
        let members = group(annotation), old = members.map { $0.1.contents }
        for (page, mark) in members { touch(page); mark.contents = text }
        undoEdits.append { for (index, member) in members.enumerated() { member.1.contents = old[index] } }
        changed()
    }
    func persistentID(for annotation: PDFAnnotation) -> String {
        if let id = annotation.value(forAnnotationKey: PDFMark.idKey) as? String { return id }
        let id = annotation.groupID ?? UUID().uuidString
        for (page, mark) in group(annotation) {
            touch(page); mark.setValue(id, forAnnotationKey: PDFMark.idKey)
        }
        changed()
        return id
    }
    func recolor(_ annotation: PDFAnnotation, to color: HighlightColor) {
        let members = group(annotation), old = members.map { $0.1.color }
        guard !members.isEmpty else { return }
        for (page, mark) in members {
            touch(page); mark.color = color.color.withAlphaComponent(mark.type == "Highlight" ? 0.45 : 1)
        }
        undoEdits.append { for (index, member) in members.enumerated() { member.1.color = old[index] } }
        changed()
    }
    func remove(_ annotation: PDFAnnotation) {
        let members = group(annotation)
        guard !members.isEmpty else { return }
        for (page, mark) in members { touch(page); page.removeAnnotation(mark) }
        focusedAnnotation = nil
        undoEdits.append { for (page, mark) in members { page.addAnnotation(mark) } }
        changed()
    }
    func undo() {
        guard let edits = undoEdits.popLast() else { return }
        edits(); focusedAnnotation = nil; changed()
    }
    private func changed() {
        dirty = true; revision += 1
        // Invalidate PDFKit's tiled page rendering, not just the outer scroll view.
        for index in touchedPages { if let page = document?.page(at: index) { view.annotationsChanged(on: page) } }
        view.annotationsChanged()
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.saveInBackground()
        }
    }
    private func snapshots() -> [Int: [PDFMark]] {
        guard let document else { return [:] }
        return Dictionary(uniqueKeysWithValues: touchedPages.compactMap { index in
            document.page(at: index).map { (index, $0.annotations.filter { $0.type == "Highlight" || $0.type == "Text" }.map(PDFMark.init)) }
        })
    }
    private func saveInBackground() {
        guard dirty else { return }
        let marks = snapshots(), currentRevision = revision, original = original, annotated = annotated
        saveQueue.async {
            let result = Result { try PDFMark.write(marks, original: original, annotated: annotated) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.revision == currentRevision else { return }
                switch result { case .success: self.dirty = false; self.error = nil
                case .failure(let error): self.error = "Changes are still open but could not be saved: " + error.localizedDescription }
            }
        }
    }
    func saveWithoutBlocking() {
        pendingSave?.cancel()
        saveInBackground()
    }
    func flushInBackground() async -> Bool {
        pendingSave?.cancel()
        guard dirty else { return true }
        let marks = snapshots(), currentRevision = revision, original = original, annotated = annotated
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            saveQueue.async { continuation.resume(returning: Result { try PDFMark.write(marks, original: original, annotated: annotated) }) }
        }
        guard revision == currentRevision else { return false }
        switch result {
        case .success: dirty = false; error = nil
        case .failure(let failure): error = "Changes are still open but could not be saved: " + failure.localizedDescription
        }
        return !dirty
    }
    // Explicit flush for close and tests. Routine edits never serialize a book on the UI thread.
    func save() {
        pendingSave?.cancel()
        guard dirty else { return }
        let marks = snapshots(), original = original, annotated = annotated
        do {
            try saveQueue.sync { try PDFMark.write(marks, original: original, annotated: annotated) }
            dirty = false; error = nil
        } catch { self.error = "Changes are still open but could not be saved: " + error.localizedDescription }
    }
    func go(to number: Int) {
        guard let page = document?.page(at: number - 1) else { return }
        initialPage = nil; pageNumber = number; view.go(to: page)
        try? JSONEncoder().encode(number).write(to: positionURL, options: .atomic)
    }
    func reveal(_ annotation: PDFAnnotation) {
        guard let page = annotation.page else { return }
        focusedAnnotation = annotation
        view.go(to: annotation.bounds.insetBy(dx: -30, dy: -40), on: page)
    }
    func find(_ text: String) {
        guard !text.isEmpty, let document else { return }
        if let selection = document.findString(text, fromSelection: view.currentSelection, withOptions: .caseInsensitive)
            ?? document.findString(text, fromSelection: nil, withOptions: .caseInsensitive) {
            view.setCurrentSelection(selection, animate: true); view.scrollSelectionToVisible(nil); error = nil
        } else { error = "No match for “\(text)”." }
    }
    func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Annotated document.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL != original.standardizedFileURL else { error = "Choose another filename to keep the original unchanged."; return }
        do {
            guard let data = document?.dataRepresentation() else { throw FrontierError("No PDF to export.") }
            try data.write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
}

private struct PDFCanvas: NSViewRepresentable {
    let source: SourcePDF
    func makeNSView(context: Context) -> PDFView {
        let page = source.pageNumber
        let document = source.document
        // PDFKit can retain a blank tiled layer after leaving the view hierarchy.
        // Reattach the same document, preserving its annotations and undo objects.
        source.view.document = nil; source.view.document = document
        DispatchQueue.main.async {
            source.view.layoutDocumentView(); source.view.autoScales = true
            source.restorePosition(fallback: page)
            source.view.needsDisplay = true; source.view.documentView?.needsDisplay = true
        }
        source.view.refreshMargin()
        return source.view
    }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}

struct SourceReader: View {
    let title: String
    @ObservedObject var source: SourcePDF
    var embedded = false
    var compact = false
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var showingAnnotations: Bool { get { source.showingNotes } nonmutating set { source.showingNotes = newValue } }
    @FocusState private var noteFocused: Bool
    init(title: String, source: SourcePDF, embedded: Bool = false, compact: Bool = false) {
        self.title = title; self.source = source; self.embedded = embedded; self.compact = compact

    }
    var body: some View {
        VStack(spacing: 0) {
            if !embedded { HStack {
                Text(title).font(.custom("Georgia", size: 18)).lineLimit(1)
                Spacer()
                Button("Export PDF…") { source.export() }.disabled(source.document == nil)
                if !embedded { Button("Done") { source.save(); if !source.dirty { dismiss() } }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("pdf-done") }
            }.padding(.horizontal, 16).padding(.top, 18) }
            ViewThatFits(in: .horizontal) {
              HStack(spacing: 8) {
                pageTools
                annotationTools
              }
              VStack(alignment: .leading, spacing: 8) { pageTools; annotationTools }
            }.padding(12)
            Divider()
            HStack(spacing: 0) {
                PDFCanvas(source: source).frame(maxWidth: .infinity, maxHeight: .infinity)
                if showingAnnotations { PDFNotesPanel(source: source, showing: $source.showingNotes) }
            }
            if let draftError = source.draftError {
                HStack { Text(draftError).font(.caption).foregroundStyle(.red); Button("Retry draft save") { source.saveNoteDraft() } }.padding(10)
            }
            if let error = source.error {
                HStack { Text(error).font(.caption).foregroundStyle(.red); if source.dirty { Button("Retry save") { source.save() } } }.padding(10)
            }
            Text(source.dirty ? "Unsaved changes" : "Annotations save automatically · Original preserved")
                .font(.system(size: 10)).foregroundStyle(LibraryTheme.muted).padding(9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LibraryTheme.paper).foregroundStyle(LibraryTheme.ink).tint(LibraryTheme.accent)
        .buttonStyle(LibrarySecondaryButton()).interactiveDismissDisabled(source.dirty)
        .onChange(of: source.focusRequest) { _, _ in if source.focusedAnnotation != nil { showingAnnotations = true } }
        .onAppear { if source.noteDraft != nil { showingAnnotations = true } }
        .onDisappear { source.saveWithoutBlocking() }
    }
    private var pageTools: some View {
        HStack(spacing: 6) {
                Button { source.go(to: source.pageNumber - 1) } label: { Image(systemName: "chevron.left") }.disabled(source.pageNumber <= 1).help("Previous page")
                    .accessibilityIdentifier("pdf-previous")
                Text("\(source.pageNumber) / \(source.pageCount)").monospacedDigit().font(.caption)
                Button { source.go(to: source.pageNumber + 1) } label: { Image(systemName: "chevron.right") }.disabled(source.pageNumber >= source.pageCount).help("Next page")
                    .accessibilityIdentifier("pdf-next")
                Button { source.view.zoomOut(nil) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out")
                Button { source.view.zoomIn(nil) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in")
                Menu { Button("Export annotated PDF…") { source.export() } } label: { Image(systemName: "ellipsis") }.menuIndicator(.hidden).fixedSize().help("PDF options")
                TextField("Find in PDF", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 150).onSubmit { source.find(search) }
                Button("Find") { source.find(search) }.disabled(search.isEmpty)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var annotationTools: some View {
        HStack(spacing: 6) {
                Menu {
                    ForEach(HighlightColor.allCases, id: \.self) { color in
                        Button { source.highlightColor = color } label: {
                            Label(color.rawValue, systemImage: source.highlightColor == color ? "checkmark.circle.fill" : "circle.fill")
                                .foregroundStyle(Color(nsColor: color.color))
                        }.accessibilityIdentifier("pdf-color-" + color.rawValue)
                    }
                } label: {
                    Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: source.highlightColor.color))
                }.fixedSize().help("Highlight color: " + source.highlightColor.rawValue)
                    .accessibilityLabel("Highlight color: " + source.highlightColor.rawValue).accessibilityIdentifier("pdf-highlight-color")
                Button("Highlight") { source.highlight() }.disabled(!source.hasSelection || source.document?.allowsCommenting != true)
                    .accessibilityIdentifier("pdf-highlight")
                Button("Add note") { beginNote() }.disabled(source.document?.allowsCommenting != true)
                    .accessibilityIdentifier("pdf-add-note")
                Button { showingAnnotations.toggle() } label: {
                    Text("Notes").foregroundStyle(showingAnnotations ? LibraryTheme.accent : LibraryTheme.ink)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(showingAnnotations ? LibraryTheme.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: 5))
                }.buttonStyle(.plain).help("Highlights and notes").accessibilityIdentifier("pdf-toggle-notes")
                Button("Undo") { source.undo() }.disabled(!source.canUndo).accessibilityIdentifier("pdf-undo")
                if source.explainSelection != nil {
                    Button("Explain") { if let text = source.view.currentSelection?.string { source.explainSelection?(text, source.view.currentSelection?.pages.first.flatMap { source.document?.index(for: $0) }.map { $0 + 1 } ?? source.pageNumber) } }.disabled(!source.hasSelection).help("Explain the selected passage with your AI")
                }
        }.fixedSize(horizontal: true, vertical: false)
    }
    private func beginNote(_ annotation: PDFAnnotation? = nil) {
        source.beginNote(annotation)
        showingAnnotations = true; noteFocused = true
    }
}

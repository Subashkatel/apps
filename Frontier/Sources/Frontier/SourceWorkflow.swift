import AppKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import LocalSupport

extension Model {
    enum ReadingMode: String, CaseIterable { case learn = "Read", source = "Original PDF", walkthrough = "Walkthrough", compare = "Side by side" }
    var activeMaterial: LibraryMaterial? { readingMaterial ?? sourceMaterial.flatMap { old in materials.first { $0.id == old.id } } ?? current.flatMap { source(for: $0) } }
    var hasUnsavedAnnotations: Bool { pdfReaders.values.contains { $0.dirty || $0.draftError != nil } }
    func pdfReader(for item: LibraryMaterial) -> SourcePDF? {
        guard let original = MaterialStore.live.existingOriginal(item), original.pathExtension.lowercased() == "pdf" else { return nil }
        let key = original.path
        if let cached = pdfReaders[key] { return cached }
        let annotated = original.deletingPathExtension().appendingPathExtension("annotated.pdf")
        let reader = SourcePDF(original: original, annotated: annotated)
        reader.notesOpened = { [weak self] in self?.showingDiscussion = false }
        reader.sendToReview = { [weak self, weak reader] annotation in
            guard let self, let reader, let page = annotation.page, !reader.sendingToReview else { return }
            let annotationID = reader.persistentID(for: annotation)
            let item = self.materials.first { $0.id == item.id } ?? item
            let quote = reader.quote(for: annotation)
            let packet = ReadingHandoff(materialID: item.id, title: item.title, origin: item.origin,
                originalPath: original.path, annotationID: annotationID,
                page: (reader.document?.index(for: page) ?? 0) + 1, quote: quote, note: reader.noteText(for: annotation))
            reader.sendingToReview = true
            Task {
                defer { reader.sendingToReview = false }
                guard await reader.flushInBackground() else {
                    if reader.error == nil { reader.error = "The annotation changed while saving. Please try Use in review again." }
                    return
                }
                do {
                    let url = try packet.write()
                    if !NSWorkspace.shared.open(url) { self.note = "Paper Notes could not be opened. Your annotation is saved; install Paper Notes and try again." }
                } catch { self.note = error.localizedDescription }
            }
        }
        reader.explainSelection = { [weak self] text, page in self?.explainPassage(text, page: page, material: item) }
        pdfReaders[key] = reader
        return reader
    }
    func attachOriginal(to item: LibraryMaterial) async throws -> LibraryMaterial? {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ResourceFiles.extensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let store = MaterialStore.live
        let updated = try await Task.detached {
            let loaded = try Resource.read(url.path)
            var updated = item
            if updated.sections.isEmpty { updated.sections = loaded.sections }
            return try store.attach(.init(filename: url.lastPathComponent, data: Data(contentsOf: url)), to: updated)
        }.value
        try saveMaterial(updated)
        return updated
    }
    func explainPassage(_ text: String, page: Int, material: LibraryMaterial) {
        showingDiscussion = true
        let chat = discussion(for: material.id)
        let question = "Explain this passage from PDF page \(page), then help me check my understanding.\n\n> " + text.prefix(24000).replacingOccurrences(of: "\n", with: "\n> ")
        let context = "Source: \(material.title). Selected passage on PDF page \(page):\n\(text.prefix(24000))\n\n" + (pdfReader(for: material)?.discussionExcerpt() ?? "")
        chat.draft = question
        Task { await chat.send(question, source: { context }, settings: { try AISettings.load() }) }
    }
    func handleSourceURL(_ url: URL) {
        guard url.scheme == "frontier", url.host == "source" else { return }
        if materials.isEmpty { load() }
        guard let item = materials.first(where: { $0.id == url.lastPathComponent }) else { note = "This source is no longer in the Frontier library."; return }
        openOriginal(item)
        guard let reader = pdfReader(for: item) else { return }
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let page = parts.first(where: { $0.name == "page" })?.value.flatMap(Int.init) ?? 1
        reader.go(to: page)
        if let id = parts.first(where: { $0.name == "annotation" })?.value,
           let annotation = reader.annotations.first(where: { $0.groupID == id }) { reader.reveal(annotation) }
    }
}

struct MaterialSource: View {
    @ObservedObject var model: Model
    let item: LibraryMaterial
    @State private var attaching = false
    var body: some View {
        Group {
            if let source = model.pdfReader(for: item) {
                SourceReader(title: item.title, source: source, embedded: true, compact: model.readingMode == .compare).id(source.original.path)
            } else {
                VStack(spacing: 16) {
                    Text(item.originalFile == nil ? "Keep the original with this material." : "Read the original document.").font(.custom("Georgia", size: 24))
                    Text(item.originalFile == nil ? "Attach the book or paper to keep its source alongside your existing lessons." : "This format opens in your preferred document app. Extracted text remains available in Learn.")
                        .foregroundStyle(LibraryTheme.muted).multilineTextAlignment(.center).frame(maxWidth: 420)
                    if let url = MaterialStore.live.existingOriginal(item) {
                        Button("Open original") { if !NSWorkspace.shared.open(url) { model.note = "No application could open this document." } }
                    }
                    Button(attaching ? "Attaching…" : "Attach original…") {
                        attaching = true
                        Task { do { _ = try await model.attachOriginal(to: item) } catch { model.note = error.localizedDescription }; attaching = false }
                    }.disabled(attaching)
                }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(LibraryTheme.paper)
    }
}

import AppKit
import SwiftUI
import PDFKit

/// One annotation editor shared by the original and formatted readers.
struct PDFNotesPanel: View {
    @ObservedObject var source: SourcePDF
    @Binding var showing: Bool
    var reveal: ((PDFAnnotation) -> Void)? = nil
    @FocusState private var noteFocused: Bool
    private func beginNote(_ mark: PDFAnnotation) { source.beginNote(mark); noteFocused = true }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Notes").font(.custom("Georgia", size: 22)).accessibilityIdentifier("pdf-margin-panel")
                Spacer(minLength: 8)
                Text("\(source.annotations.count) \(source.annotations.count == 1 ? "note" : "notes")")
                    .font(.system(size: 11)).foregroundStyle(LibraryTheme.muted)
                Button { showing = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close notes")
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if source.annotations.isEmpty {
                            Text("A question, a connection, a thought. Select a passage to highlight it or keep a note here.")
                                .font(.system(size: 12)).lineSpacing(5).foregroundStyle(LibraryTheme.muted)
                                .padding(.bottom, 20)
                        }
                        ForEach(source.annotations, id: \.stableID) { annotation in
                            marginEntry(annotation).id(annotation.stableID)
                        }
                    }.padding(.horizontal, 20)
                }
                .onAppear {
                    if let annotation = source.focusedAnnotation {
                        DispatchQueue.main.async { proxy.scrollTo(annotation.stableID, anchor: .center) }
                    }
                }
                .onChange(of: source.focusRequest) { _, _ in
                    if let annotation = source.focusedAnnotation {
                        // Give the newly opened panel a layout pass before locating the entry.
                        DispatchQueue.main.async { proxy.scrollTo(annotation.stableID, anchor: .center) }
                    }
                }
            }
            if source.noteDraft != nil { noteComposer }
        }
        .frame(width: 280).frame(maxHeight: .infinity)
        .background(LibraryTheme.paper)
        .overlay(alignment: .leading) { LibraryTheme.rule.frame(width: 1) }
    }
    private func marginEntry(_ annotation: PDFAnnotation) -> some View {
        let selected = source.focusedAnnotation?.stableID == annotation.stableID
        let quote = source.quote(for: annotation)
        let text = source.noteText(for: annotation)
        let page = (annotation.page.flatMap { source.document?.index(for: $0) } ?? 0) + 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(annotation.type == "Highlight" ? "Highlight" : "Note") · Page \(page)")
                Spacer()
                Menu {
                    Menu("Change color") {
                        ForEach(HighlightColor.allCases, id: \.self) { color in
                            Button(color.rawValue) { source.recolor(annotation, to: color) }
                        }
                    }
                    Button("Remove", role: .destructive) {
                        if source.noteDraft?.annotationID == annotation.groupID { source.noteDraft = nil }
                        source.remove(annotation)
                    }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Annotation actions").accessibilityLabel("Actions for annotation on page \(page)")
            }.font(.system(size: 11)).foregroundStyle(LibraryTheme.muted)
            if !quote.isEmpty {
                Text(quote).font(.custom("Georgia-Italic", size: 14)).lineSpacing(4)
                    .foregroundStyle(LibraryTheme.muted).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Color(nsColor: annotation.color.withAlphaComponent(1)).frame(width: 2) }
            }
            if !text.isEmpty {
                Text(text).font(.system(size: 12)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { marginActions(annotation) }
                VStack(alignment: .leading, spacing: 9) { marginActions(annotation) }
            }
            .font(.system(size: 11)).foregroundStyle(LibraryTheme.accent).buttonStyle(.plain)
        }
        .padding(.leading, selected ? 12 : 0)
        .overlay(alignment: .leading) { if selected { LibraryTheme.accent.frame(width: 2) } }
        .padding(.bottom, 22).padding(.top, 16)
        .overlay(alignment: .bottom) { LibraryTheme.rule.frame(height: 1) }
    }
    @ViewBuilder private func marginActions(_ annotation: PDFAnnotation) -> some View {
        Button("Show passage") { if let reveal { reveal(annotation) } else { source.reveal(annotation) } }
        Button("Edit") { beginNote(annotation) }.accessibilityIdentifier("pdf-edit-" + annotation.stableID)
        if source.sendToReview != nil {
            Button(source.sendingToReview ? "Sending…" : "Use in review ↗") { source.sendToReview?(annotation) }.disabled(source.sendingToReview).help("Add this passage and note to Paper Notes")
        }
    }
    private var noteComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(source.noteDraft?.annotationID == nil ? "Your note" : "Edit your note").font(.system(size: 12, weight: .medium))
            let quote = source.noteDraft?.quote ?? ""
            if !quote.isEmpty {
                Text(quote).font(.custom("Georgia-Italic", size: 12)).foregroundStyle(LibraryTheme.muted).lineLimit(3)
            } else {
                Text("Page \((source.noteDraft?.page ?? (source.pageNumber - 1)) + 1)")
                    .font(.system(size: 11)).foregroundStyle(LibraryTheme.muted)
            }
            TextEditor(text: Binding(get: { source.noteDraft?.text ?? "" }, set: { source.noteDraft?.text = $0 })).font(.system(size: 12)).lineSpacing(4)
                .scrollContentBackground(.hidden).padding(8).frame(height: 100)
                .background(LibraryTheme.chrome, in: .rect(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(LibraryTheme.rule, lineWidth: 1))
                .focused($noteFocused).disabled(source.savingNote).accessibilityIdentifier("pdf-note-editor")
            HStack {
                Button("Cancel") { source.noteDraft = nil; noteFocused = false }.disabled(source.savingNote)
                    .buttonStyle(.plain).foregroundStyle(LibraryTheme.muted).accessibilityIdentifier("pdf-cancel-note")
                Spacer()
                Button(source.savingNote ? "Saving…" : "Keep note") {
                    Task { if await source.commitNoteDraft() { noteFocused = false } }
                }.buttonStyle(LibraryPrimaryButton())
                    .disabled(source.savingNote || (source.noteDraft?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
                    .accessibilityIdentifier("pdf-keep-note")
            }.font(.system(size: 11))
        }.onAppear { noteFocused = true }.padding(20).overlay(alignment: .top) { LibraryTheme.rule.frame(height: 1) }
    }
}

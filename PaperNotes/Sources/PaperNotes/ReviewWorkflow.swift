import SwiftUI
import AppKit
import LocalSupport

/// These are additions to the reader's Markdown, never replacements for it.
enum ReviewPrompt: String, CaseIterable {
    case claim = "Claim, in my words", evidence = "Evidence — what convinced me, or didn't"
    case assumptions = "This would be wrong if", understanding = "What I understood"
    case gaps = "What I didn't understand", connections = "Connections"
}

enum ReviewHandoff {
    static func key(_ packet: ReadingHandoff) -> String {
        let origin = URL(string: packet.origin)
        let isArxiv = ["arxiv.org", "www.arxiv.org", "export.arxiv.org"].contains(origin?.host?.lowercased() ?? "")
        let key = isArxiv ? PDFRefs.normalise(PDFRefs.idFromFilename(packet.origin) ?? "") : ""
        return Paper.isArxivID(key) ? key : "frontier-" + packet.materialID
    }
    static func append(_ packet: ReadingHandoff, to paper: inout Paper) -> Bool {
        let marker = "<!-- frontier-annotation:\(packet.materialID):\(packet.annotationID) -->"
        guard !paper.body.contains(marker) else { return false }
        let quote = packet.quote.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n")
        paper.body += "\n\n" + marker + "\n\n### Passage · page \(packet.page)\n\n" + quote
        if !packet.note.isEmpty && packet.note != packet.quote { paper.body += "\n\n" + packet.note }
        paper.body += "\n\n[Return to source · page \(packet.page)](\(packet.sourceURL.absoluteString))\n"
        return true
    }
}

extension AppModel {
    func receive(_ url: URL) {
        bootstrap()
        guard flushDraft() else { return }
        do {
            let packet = try ReadingHandoff.read(url)
            Library.shared.reload()
            let key = ReviewHandoff.key(packet)
            var paper = Library.shared.paper(withID: key) ?? Paper(arxivID: key)
            if paper.title.isEmpty { paper.title = packet.title }
            if paper.resolvedPDF == nil {
                guard let path = Library.adopt(URL(fileURLWithPath: packet.originalPath), for: key) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                paper.pdfPath = path
            }
            let added = ReviewHandoff.append(packet, to: &paper)
            guard Library.shared.save(paper) != nil else {
                saveError = "The passage could not be saved to your review. Your existing notes are kept; try Use in review again."
                return
            }
            refresh(); select(key)
            status = added ? "Passage added from Frontier · page \(packet.page)" : "This passage is already in your review"
        } catch { saveError = "Could not receive this passage: " + error.localizedDescription }
    }
    func appendPrompt(_ prompt: ReviewPrompt) {
        guard draft != nil else { return }
        let heading = "## " + prompt.rawValue
        if draft?.body.components(separatedBy: .newlines).contains(heading) != true {
            draft?.body += "\n\n" + heading + "\n\n"
        }
        UserDefaults.standard.set("Write", forKey: "reviewMode")
    }
    func connect(to id: String, reason: String) {
        guard let own = draft?.id, own != id, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft?.connections[id] = reason
        if flushDraft() { refresh() }
    }
}

enum ReviewTheme {
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 34/255, green: 37/255, blue: 31/255, alpha: 1)
            : NSColor(srgbRed: 0.97, green: 0.96, blue: 0.92, alpha: 1)
    })
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.77, green: 0.82, blue: 0.67, alpha: 1)
            : NSColor(srgbRed: 0.35, green: 0.42, blue: 0.26, alpha: 1)
    })
}

struct ReviewConnections: View {
    @Bindable var model: AppModel
    @State private var choosing = false
    @State private var target = ""
    @State private var reason = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Connections").font(.custom("Georgia", size: 17)); Spacer()
                Button("Add connection") { target = model.papers.first { $0.id != model.draft?.id }?.id ?? ""; reason = ""; choosing = true }
                    .disabled(model.papers.count < 2)
            }
            if model.related.isEmpty { Text("Connections appear from shared references, related topics, or a reason you write.").foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.related) { relation in
                        HStack(alignment: .top) {
                            Button { model.select(relation.other.id) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(relation.other.title).lineLimit(2)
                                    Text(relation.explanation).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            if model.draft?.connections[relation.other.id] != nil {
                                Button("Remove") { model.draft?.connections.removeValue(forKey: relation.other.id); if model.flushDraft() { model.refresh() } }.font(.caption)
                            }
                        }
                    }
                }
            }.frame(maxHeight: 130)
        }.font(.system(size: 12))
        .sheet(isPresented: $choosing) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Connect two papers").font(.custom("Georgia", size: 24))
                Picker("Paper", selection: $target) {
                    ForEach(model.papers.filter { $0.id != model.draft?.id }) { Text($0.title.isEmpty ? $0.id : $0.title).tag($0.id) }
                }
                TextField("Why do these papers connect?", text: $reason, axis: .vertical).lineLimit(3...5)
                HStack { Button("Cancel") { choosing = false }; Spacer(); Button("Save connection") { model.connect(to: target, reason: reason); choosing = false }.disabled(target.isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(24).frame(width: 460).background(ReviewTheme.surface)
        }
    }
}

struct ReviewRowSelection: ViewModifier {
    let id: String
    @Binding var selection: Set<String>
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            .background(selection.contains(id) ? ReviewTheme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.command) {
                    if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                } else { selection = [id] }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selection = [id] }
    }
}

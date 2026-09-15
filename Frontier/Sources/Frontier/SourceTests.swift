import AppKit
import PDFKit
import LocalSupport

@MainActor enum SourceTests {
    static func run(_ check: (String, Bool, String) -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("source-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func verify(_ name: String, _ ok: Bool) { check(name, ok, "") }
        let indexed = PassageTextIndex("🙂 A sufficiently long\n  selected passage ends here.")
        let matches = indexed.ranges(matching: "A sufficiently long selected passage")
        verify("article anchor preserves UTF-16 positions across whitespace", matches.count == 1 && ("🙂 A sufficiently long\n  selected passage ends here." as NSString).substring(with: matches[0]).contains("selected passage"))
        verify("repeated article text is explicitly ambiguous", PassageTextIndex("A repeated passage here. A repeated passage here.").ranges(matching: "A repeated passage here.").count == 2)
        verify("short and absent article anchors do not guess a location", indexed.ranges(matching: "short").isEmpty && indexed.ranges(matching: "absent passage here").isEmpty)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let original = root.appendingPathComponent("original.pdf")
            var box = CGRect(x: 0, y: 0, width: 420, height: 600)
            let context = CGContext(original as CFURL, mediaBox: &box, nil)!
            for number in 1...2 {
                context.beginPDFPage(nil)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                ("Evidence on page \(number)" as NSString).draw(at: CGPoint(x: 40, y: 500), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
                ("A second line of evidence" as NSString).draw(at: CGPoint(x: 40, y: 470), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
                NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
            }
            context.closePDF()
            let bytes = try Data(contentsOf: original)
            let loaded = try Resource.document(bytes, filename: "2510.21600.pdf", origin: "https://arxiv.org/abs/2510.21600")
            verify("downloaded original survives extraction", loaded.original?.data == bytes && !loaded.sections.isEmpty)
            let store = MaterialStore(root: root.appendingPathComponent("materials"))
            let item = try store.add(loaded)
            verify("remote original is attached to library item", store.existingOriginal(item).flatMap { try? Data(contentsOf: $0) } == bytes)
            verify("arXiv URL variants resolve to one source", Resource.canonicalOrigin("https://arxiv.org/pdf/2510.21600.pdf") == loaded.origin && Resource.arxivID(URL(string: "https://arxiv.org/html/2510.21600v2")!) == "2510.21600v2")
            let annotated = root.appendingPathComponent("annotated.pdf")
            let reader = SourcePDF(original: original, annotated: annotated)
            let previousColor = reader.highlightColor
            defer { reader.highlightColor = previousColor }
            reader.highlightColor = .red
            let selection = reader.document?.findString("Evidence", fromSelection: nil, withOptions: [])
            verify("PDF text can be selected", selection != nil)
            reader.view.setCurrentSelection(selection, animate: false); reader.highlight(); reader.save()
            verify("highlight is saved as a PDF annotation", !reader.dirty && reader.annotations.count == 1 && PDFDocument(url: annotated)?.page(at: 0)?.annotations.count == 1)
            if let annotation = reader.annotations.first {
                verify("highlight then Add note targets the same passage", reader.noteTarget === annotation && reader.quote(for: annotation) == "Evidence")
                verify("chosen highlight color persists", abs((PDFDocument(url: annotated)?.page(at: 0)?.annotations.first?.color.usingColorSpace(.deviceRGB)?.redComponent ?? 0) - 0.93) < 0.02)
                reader.go(to: 2)
                verify("Add note does not reuse a highlight from another page", reader.noteTarget == nil)
                reader.go(to: 1)
                reader.edit(annotation, text: "My critical note"); reader.save()
                verify("annotation edits persist", PDFDocument(url: annotated)?.page(at: 0)?.annotations.first?.contents == "My critical note")
                let saved = SourcePDF(original: original, annotated: annotated)
                if let mark = saved.annotations.first {
                    verify("quote and personal note remain separate after PDF reopen", saved.quote(for: mark) == "Evidence" && saved.noteText(for: mark) == "My critical note")
                } else { verify("quote and personal note remain separate after PDF reopen", false) }
                reader.undo()
                verify("plain highlight does not duplicate quote as personal note", reader.noteText(for: annotation).isEmpty)
                verify("undo restores annotation text", annotation.contents == "Evidence")
                reader.remove(annotation); verify("annotation removal persists", reader.annotations.isEmpty)
                reader.undo(); reader.save(); verify("undo restores removed annotation", reader.annotations.count == 1)
            }
            let countBefore = reader.annotations.count
            if let page = reader.document?.page(at: 0) {
                reader.view.setCurrentSelection(page.selection(for: page.bounds(for: .cropBox)), animate: false)
                reader.highlight(note: "Whole passage")
                verify("multiline highlight is one margin entry", reader.annotations.count == countBefore + 1)
                let grouped = reader.annotations.first { $0.contents == "Whole passage" }!
                reader.recolor(grouped, to: .green); reader.save()
                let groupID = grouped.value(forAnnotationKey: PDFMark.idKey) as? String
                let savedDocument = PDFDocument(url: annotated)
                withExtendedLifetime(savedDocument) {
                    let savedMarks = savedDocument?.page(at: 0)?.annotations.filter { $0.value(forAnnotationKey: PDFMark.idKey) as? String == groupID } ?? []
                    check("changing highlight color persists for every line", savedMarks.count > 1 && savedMarks.allSatisfy { abs(($0.color.usingColorSpace(.deviceRGB)?.greenComponent ?? 0) - 0.72) < 0.02 }, "count=\(savedMarks.count), colors=\(savedMarks.map { String(describing: $0.color) })")
                }
                reader.undo()
                verify("undo restores every line's previous color", page.annotations.filter { $0.value(forAnnotationKey: PDFMark.idKey) as? String == groupID }.allSatisfy { abs(($0.color.usingColorSpace(.deviceRGB)?.redComponent ?? 0) - 0.93) < 0.02 })
                reader.remove(grouped); reader.save()
                verify("removing multiline highlight removes every line", page.annotations.allSatisfy { $0.contents != "Whole passage" } && reader.annotations.count == countBefore)
            }
            reader.addNote("A margin question"); reader.save()
            let sticky = reader.annotations.first { $0.type == "Text" }!
            reader.remove(sticky); reader.save()
            verify("deleted sticky note stays deleted after reopen", SourcePDF(original: original, annotated: annotated).annotations.allSatisfy { $0.type != "Text" })
            reader.undo(); reader.save()
            verify("undo restores deleted sticky note", reader.annotations.contains { $0.type == "Text" })
            reader.remove(reader.annotations.first { $0.type == "Text" }!); reader.save()
            reader.view.setCurrentSelection(selection, animate: false)
            let anchor = reader.noteAnchor()
            reader.view.clearSelection(); reader.go(to: 2)
            reader.addNote("Anchored thought", at: anchor); reader.save()
            let anchoredReader = SourcePDF(original: original, annotated: annotated)
            if let mark = anchoredReader.annotations.first(where: { $0.contents == "Anchored thought" }) {
                verify("note retains selected passage and page while reader navigates", anchoredReader.quote(for: mark) == "Evidence" && mark.page === anchoredReader.document?.page(at: 0))
            } else { verify("note retains selected passage and page while reader navigates", false) }
            if let mark = reader.annotations.first(where: { $0.contents == "Anchored thought" }) { reader.remove(mark); reader.save() }
            verify("annotation work leaves original bytes unchanged", try Data(contentsOf: original) == bytes)
            let reopened = SourcePDF(original: original, annotated: annotated)
            verify("annotations survive reopening", reopened.annotations.count == 1)
            reader.go(to: 2)
            let resumed = SourcePDF(original: original, annotated: annotated)
            resumed.restorePosition()
            verify("source page survives reopening", resumed.pageNumber == 2)
            let excerpt = reader.discussionExcerpt()
            verify("discussion follows the current PDF page", excerpt.contains("[PDF page 2 — current page]") && excerpt.contains("Evidence on page 2") && excerpt.contains("[PDF page 1]"))
            reader.view.setCurrentSelection(selection, animate: false)
            reader.beginNote()
            reader.noteDraft?.text = "My unfinished reasoning"
            reader.view.clearSelection(); reader.go(to: 2)
            let draftReader = SourcePDF(original: original, annotated: annotated)
            verify("unfinished annotation draft survives reopening with passage anchor", draftReader.noteDraft?.text == "My unfinished reasoning" && draftReader.noteDraft?.quote == "Evidence" && draftReader.noteDraft?.page == 0)
            draftReader.beginNote()
            verify("starting another note does not discard an unfinished thought", draftReader.noteDraft?.text == "My unfinished reasoning")
            verify("restored draft can be kept", draftReader.keepNoteDraft())
            draftReader.save()
            let keptCount = draftReader.annotations.count
            verify("retrying Keep does not create duplicate annotations", draftReader.keepNoteDraft() && draftReader.annotations.count == keptCount)
            draftReader.save(); draftReader.noteDraft = nil
            verify("kept note retains source quote after reopen", SourcePDF(original: original, annotated: annotated).annotations.contains { $0.contents == "My unfinished reasoning" && $0.value(forAnnotationKey: PDFMark.quoteKey) as? String == "Evidence" })
            verify("saved note clears its recovered composer", SourcePDF(original: original, annotated: annotated).noteDraft == nil)
            var collection = LibraryMaterial(id: "existing-course", title: "Existing course", kind: .course, format: "Collection", conceptIDs: ["lesson-1", "lesson-2"], courseName: "Existing course")
            collection.notes = "My existing course notes"
            let attached = try store.attach(.init(filename: "course.pdf", data: bytes), to: collection)
            verify("attaching an original preserves course lessons and notes", attached.conceptIDs == collection.conceptIDs && attached.notes == collection.notes && attached.id == collection.id)
            verify("formatted reader preserves explicit arXiv version", FormattedArticle.sourceURL(origin: "https://arxiv.org/abs/2510.21600v2", original: nil)?.absoluteString == "https://arxiv.org/html/2510.21600v2")
            verify("unidentified local PDFs keep original layout", FormattedArticle.sourceURL(origin: original.path, original: original) == nil)
            let packet = ReadingHandoff(materialID: item.id, title: item.title, origin: item.origin, originalPath: original.path, annotationID: UUID().uuidString, page: 2, quote: "Evidence", note: "Does this generalize?")
            let inbox = root.appendingPathComponent("inbox")
            let url = try packet.write(to: inbox)
            let decoded = try ReadingHandoff.read(url, from: inbox)
            verify("handoff preserves passage and exact source location", decoded.note == packet.note && decoded.sourceURL.absoluteString.contains("page=2"))
            do { _ = try ReadingHandoff.read(URL(string: "papernotes://handoff/../../outside")!, from: inbox); verify("handoff rejects arbitrary paths", false) } catch { verify("handoff rejects arbitrary paths", true) }
        } catch { check("source workflow", false, error.localizedDescription) }
    }
}

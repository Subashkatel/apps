import AppKit
import WebKit
import PDFKit

@MainActor enum ArticleReadingChecks {
    static func run(web: WKWebView, view: NSView, model: Model) async throws {
        guard let material = model.activeMaterial, let source = model.pdfReader(for: material) else { throw FrontierError("Missing article source") }
        let originalBytes = try Data(contentsOf: source.original)
        let passage = "It matches the logical error performance of a floating-point implementation despite using reduced precision arithmetic."
        let clock = ContinuousClock(), started = clock.now
        try await source.selectArticlePassage(passage)
        print("Article-to-PDF first match: \(started.duration(to: clock.now))")
        let selectedPDF = source.view.currentSelection?.string ?? ""
        print("Matched PDF passage:", selectedPDF)
        guard PassageTextIndex(selectedPDF).text == PassageTextIndex(passage).text else { throw FrontierError("Wrong source match") }
        do {
            try await source.selectArticlePassage("This fabricated passage does not occur in the paper.")
            throw FrontierError("Missing passage was silently matched")
        } catch let error as FrontierError where error.localizedDescription.contains("matched uniquely") {}
        let selectionResult = try await web.callAsyncJavaScript("""
        const map=textMap(),needle=normalizedText(passage),start=map.text.indexOf(needle);
        if(start<0||map.text.indexOf(needle,start+1)>=0)throw Error('Ambiguous fixture passage');
        const a=map.positions[start],b=map.positions[start+needle.length-1],range=document.createRange();
        range.setStart(a.node,a.offset);range.setEnd(b.node,b.end);const selection=getSelection();selection.removeAllRanges();selection.addRange(range);
        range.startContainer.parentElement.scrollIntoView({block:'center'});return selection.toString();
        """, arguments: ["passage": passage], in: nil, contentWorld: .page)
        print("Selected passage:",selectionResult as Any)
        try await Task.sleep(for: .milliseconds(250))
        guard let add = ReaderPreview.accessibilityElement(view, id: "article-add-note"), ReaderPreview.press(add) else { throw FrontierError("Formatted Add note unavailable") }
        for _ in 0..<150 { if source.noteDraft != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
        guard source.noteDraft != nil else { throw FrontierError("Formatted note did not retain a PDF anchor") }
        source.noteDraft?.text = "My source-linked reading note."
        try await Task.sleep(for: .milliseconds(250))
        guard let keep = ReaderPreview.accessibilityElement(view, id: "pdf-keep-note"), ReaderPreview.press(keep) else { throw FrontierError("Shared Keep note unavailable") }
        for _ in 0..<150 { if source.noteDraft == nil { break }; try await Task.sleep(for: .milliseconds(50)) }
        guard source.noteDraft == nil, !source.dirty, let mark = source.annotations.first else { throw FrontierError("Formatted note failed to save") }
        let persisted = SourcePDF(original: source.original, annotated: source.annotated)
        guard persisted.annotations.contains(where: { persisted.noteText(for: $0) == "My source-linked reading note." }) else { throw FrontierError("Saved formatted note was absent from the PDF") }
        try await Task.sleep(for: .milliseconds(300))
        let counts = try await web.evaluateJavaScript("({marks:document.querySelectorAll('.frontier-note').length,math:document.querySelectorAll('math').length,figures:document.querySelectorAll('figure').length})")
        print("Annotated article:",counts as Any)
        guard ((try await web.evaluateJavaScript("document.querySelectorAll('.frontier-note').length")) as? Int ?? 0) > 0 else { throw FrontierError("No marker beside formatted passage") }
        model.showingDiscussion = true
        try await Task.sleep(for: .milliseconds(150))
        guard !source.showingNotes else { throw FrontierError("Discussion crowded the note panel") }
        source.showingNotes = true
        try await Task.sleep(for: .milliseconds(150))
        guard !model.showingDiscussion else { throw FrontierError("Notes failed to close discussion") }
        let before = source.focusRequest
        _ = try await web.evaluateJavaScript("document.querySelector('.frontier-note').click();true")
        try await Task.sleep(for: .milliseconds(150))
        guard source.focusRequest > before else { throw FrontierError("Margin marker did not focus shared note") }
        source.recolor(mark, to: .green)
        guard await source.flushInBackground() else { throw FrontierError("Color save failed") }
        let snapshot = try Data(contentsOf: source.annotated)
        try FileManager.default.removeItem(at: source.annotated)
        try FileManager.default.createDirectory(at: source.annotated, withIntermediateDirectories: false)
        source.beginNote(mark); source.noteDraft?.text = "A draft preserved through a failed save."
        guard !(await source.commitNoteDraft()), source.noteDraft != nil, source.dirty else { throw FrontierError("Save failure lost the note draft") }
        try FileManager.default.removeItem(at: source.annotated)
        try snapshot.write(to: source.annotated)
        guard await source.commitNoteDraft(), source.noteDraft == nil else { throw FrontierError("Save retry did not recover") }
        let restored = SourcePDF(original: source.original, annotated: source.annotated)
        guard restored.annotations.count == 1, restored.annotations.first.map({ restored.noteText(for: $0) }) == "A draft preserved through a failed save." else { throw FrontierError("Retry duplicated or lost note") }
        source.remove(mark)
        guard await source.flushInBackground() else { throw FrontierError("Deletion failed") }
        try await Task.sleep(for: .milliseconds(200))
        guard (try await web.evaluateJavaScript("document.querySelectorAll('.frontier-note').length")) as? Int == 0,
              SourcePDF(original: source.original, annotated: source.annotated).annotations.isEmpty else { throw FrontierError("Deleted marker or note survived") }
        guard try Data(contentsOf: source.original) == originalBytes else { throw FrontierError("Original was modified") }
        // Leave a saved annotation for the design capture.
        try await source.selectArticlePassage(passage); source.highlight(note: "A concrete comparison, but I still want to inspect its assumptions.")
        _ = await source.flushInBackground()
        print("PASS native formatted selection → shared note/save/reopen, margin focus, recolor, injected save failure/retry, removal and original preservation")
    }
}

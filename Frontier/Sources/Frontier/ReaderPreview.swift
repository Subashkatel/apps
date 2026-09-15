import AppKit
import SwiftUI
import WebKit

/// Exercises the actual reader layout with synthetic content and no AI or user files.
@MainActor enum ReaderPreview {
    static func webViews(_ view: NSView) -> [WKWebView] {
        (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews)
    }
    // SwiftUI exposes virtual nodes without formally adopting the AppKit
    // protocol. Invoke their public accessibility selectors for native UI tests.
    static func accessibilityProperty(_ item: NSObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard item.responds(to: selector) else { return nil }
        return item.perform(selector)?.takeUnretainedValue()
    }
    static func accessibilityElement(_ value: Any, id: String, depth: Int = 0) -> NSObject? {
        guard depth < 30, let item = value as? NSObject else { return nil }
        if accessibilityProperty(item, "accessibilityIdentifier") as? String == id { return item }
        for child in accessibilityProperty(item, "accessibilityChildren") as? [Any] ?? [] {
            if let found = accessibilityElement(child, id: id, depth: depth + 1) { return found }
        }
        return nil
    }
    static func press(_ item: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard item.responds(to: selector) else { return false }
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(item.method(for: selector), to: Press.self)(item, selector)
    }

    static func checkNavigation(model: Model, view: NSView) async throws {
        var renderer: WKWebView?
        for _ in 0..<150 {
            renderer = webViews(view).first
            if let renderer, (try? await renderer.evaluateJavaScript("document.querySelectorAll('#out .katex').length")) as? Int == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let renderer else { throw FrontierError("No course renderer") }
        try await Task.sleep(for: .milliseconds(400))
        let courseID = "course-" + model.concepts[0].courses[0]
        guard let course = accessibilityElement(view, id: courseID), press(course) else {
            func dump(_ value: Any, depth: Int = 0) {
                guard depth < 8, let item = value as? NSObject else { return }
                print(String(repeating: " ", count: depth), type(of: value), accessibilityProperty(item, "accessibilityIdentifier") as Any, accessibilityProperty(item, "accessibilityLabel") as Any)
                for child in accessibilityProperty(item, "accessibilityChildren") as? [Any] ?? [] { dump(child, depth: depth + 1) }
            }
            dump(view)
            throw FrontierError("The native course disclosure button did not respond.")
        }
        try await Task.sleep(for: .milliseconds(200))
        var latencies: [Double] = []
        for index in [1, 2, 3, 1, 2, 0] {
            let c = model.concepts[index]
            guard let row = accessibilityElement(view, id: "concept-row-" + c.id) else { throw FrontierError("Missing accessible row \(index)") }
            let started = Date()
            guard press(row) else { throw FrontierError("Row press failed for \(index)") }
            var rendered = false
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(10))
                let title = (try? await renderer.evaluateJavaScript("document.querySelector('#out h1')?.textContent")) as? String
                if model.selected == c.id && title == c.title { rendered = true; break }
            }
            guard rendered else { throw FrontierError("Selecting course row \(index) did not display its content.") }
            guard webViews(view).first === renderer else { throw FrontierError("A course click recreated the web renderer.") }
            latencies.append(Date().timeIntervalSince(started) * 1000)
        }
        for index in [1, 2, 3] {
            guard let row = accessibilityElement(view, id: "concept-row-" + model.concepts[index].id), press(row) else { throw FrontierError("Rapid course selection failed.") }
        }
        try await Task.sleep(for: .milliseconds(300))
        guard model.selected == model.concepts[3].id,
              (try await renderer.evaluateJavaScript("document.querySelector('#out h1')?.textContent")) as? String == model.concepts[3].title else {
            throw FrontierError("Rapid clicks left an earlier lesson on screen.")
        }
        print("PASS native course disclosure and row presses display the selected lesson; quick clicks show the latest selection")
        print("Course click-to-render ms: " + latencies.map { String(format: "%.0f", $0) }.joined(separator: ", "))
        print("PASS course selections reuse one renderer across 197 lessons")
    }

    static func capture(_ view: NSView, to destination: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw FrontierError("Could not capture the test view.") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw FrontierError("Could not encode the test view.") }
        try data.write(to: destination)
    }
    static func run(to destination: URL) -> Never {
        setbuf(stdout, nil)
        Task { @MainActor in
            do {
                var concept = Concept(id: "reading-check", title: "Understanding probability")
                concept.body = "## A useful starting point\n\nA probability lies between zero and one. "
                    + "For independent events, $P(A \\cap B) = P(A)P(B)$.\n\n"
                    + "$$\\sum_{i=1}^{n} p_i = 1$$\n\n"
                    + "| Event | Probability |\n| --- | --- |\n| Heads | 0.5 |\n| Tails | 0.5 |\n\n"
                    + String(repeating: "## Work through an example\n\nA fair coin gives either outcome with equal probability. Consider two independent tosses and multiply their probabilities.\n\n", count: 30)
                concept.courses = ["Example course"]
                let navigation = CommandLine.arguments.contains("--preview-navigation")
                let unwritten = CommandLine.arguments.contains("--preview-unwritten") || navigation
                let graph = CommandLine.arguments.contains("--preview-graph") || CommandLine.arguments.contains("--preview-graph-focus")
                if unwritten {
                    concept.title = "The Book’s Arc: From the Liberation of Algebra to Tensors and General Relativity"
                    concept.body = ""
                    concept.relevance = String(repeating: "A surprising story of space, time, and mathematical transformation, from the liberation of algebra to the geometry of spacetime. ", count: CommandLine.arguments.contains("--short") ? 2 : 10) + #" The metric is $ds^2 = g_{\mu\nu}\,dx^\mu dx^\nu$."#
                }
                let model = Model(concepts: [concept])
                if unwritten {
                    model.concepts[0].courses = ["Vector: A Surprising Story of Space, Time, and Mathematical Transformation"]
                    for i in 1...(navigation ? 196 : 2) {
                        var next = Concept(id: "following-\(i)", title: "The next chapter in the story")
                        next.title = "Chapter \(i): Understanding the geometry of space"
                        next.relevance = #"Learn to interpret the metric $ds^2 = g_{\mu\nu} dx^\mu dx^\nu$."#
                        next.requires = [concept.id]
                        next.courses = model.concepts[0].courses
                        model.concepts.append(next)
                    }
                }
                model.selected = concept.id
                model.screen = .read
                if graph {
                    model.concepts = (0..<197).map { i in
                        var c = Concept(id: "node-\(i)", title: "Concept \(i)")
                        if i == 1 { c.title = #"Geometry: $x^2 + y^2$"#; c.relevance = #"The metric is $ds^2 = g_{\mu\nu} dx^\mu dx^\nu$."# }
                        c.requires = i == 0 ? [] : ["node-\(i-1)", "node-\(max(0,i-5))"]
                        return c
                    }
                    model.selected = "node-0"
                    model.screen = .graph
                }
                let app = NSApplication.shared
                app.setActivationPolicy(.accessory)
                if navigation || CommandLine.arguments.contains("--preview-learning-start") || CommandLine.arguments.contains("--preview-source") || CommandLine.arguments.contains("--preview-compare") || CommandLine.arguments.contains("--preview-article") {
                    app.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
                }
                app.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
                let library = CommandLine.arguments.contains("--preview-actual-covers") || CommandLine.arguments.contains("--preview-library") || CommandLine.arguments.contains("--preview-paper-covers")
                let panel = CommandLine.arguments.contains("--preview-ai") || CommandLine.arguments.contains("--preview-import") || CommandLine.arguments.contains("--preview-detail")
                var content = AnyView(ContentView(model: model, loadsOnAppear: false, previewGraphHover: graph && !CommandLine.arguments.contains("--preview-graph-focus") ? "node-1" : nil))
                if library || CommandLine.arguments.contains("--preview-detail") {
                    let titles = ["AFS: Accurate, Fast, and Scalable Error-Decoding for Fault-Tolerant Quantum Computers", "Probability & inference", "Attention and memory", "Designing learning systems", "An introduction to causal thinking", "Notes on optimization", "Algorithms for everyday problems", "A research notebook"]
                    if !CommandLine.arguments.contains("--preview-actual-covers") {
                    model.materials = titles.enumerated().map { index, title in
                        var item = LibraryMaterial(id: "preview-\(index)", title: title, kind: CommandLine.arguments.contains("--preview-paper-covers") && index < 3 ? .paper : index % 3 == 0 ? .book : (index % 3 == 1 ? .paper : .note), format: index % 2 == 0 ? "EPUB" : "PDF", sections: [.init(title: "First chapter", text: concept.body)])
                        if CommandLine.arguments.contains("--preview-paper-covers") { item.added = Date(timeIntervalSince1970: Double(100 - index)); item.format = "PDF" }
                        if index < 2 { item.lastOpened = Date() }
                        return item
                    }
                    } else { model.load() }
                    model.screen = .library
                    if !library { content = AnyView(MaterialDetail(model: model, original: model.materials[0])) }
                }
                if CommandLine.arguments.contains("--preview-ai") {
                    var settings = AISettings(); settings.provider = .server
                    settings.endpoint = "http://localhost:1234/v1"; settings.serverModel = "my-local-model"
                    content = AnyView(AISettingsView(previewSettings: settings))
                } else if CommandLine.arguments.contains("--preview-import") {
                    content = AnyView(ImportSheet(model: model, previewResource: Resource.Loaded(name: "Probability handbook", origin: "/example/book.epub",
                        sections: [.init(title: "1. Probability", text: "A probability is a number between zero and one."),
                                   .init(title: "2. Independent events", text: "Multiply independent probabilities.")])))
                }
                let fallbackPreview = CommandLine.arguments.contains("--preview-learning-start")
                let articlePreview = CommandLine.arguments.contains("--preview-article")
                let sourcePreview = fallbackPreview || articlePreview || CommandLine.arguments.contains("--preview-source") || CommandLine.arguments.contains("--preview-compare")
                if sourcePreview {
                    guard let at = CommandLine.arguments.firstIndex(of: "--source-file"), CommandLine.arguments.count > at + 1 else { throw FrontierError("Pass a PDF using --source-file") }
                    let file = URL(fileURLWithPath: CommandLine.arguments[at + 1])
                    let original = try Resource.document(Data(contentsOf: file), filename: file.lastPathComponent, origin: fallbackPreview ? file.path : "https://arxiv.org/abs/2510.21600")
                    let material = try MaterialStore.live.add(original)
                    if let fixture = ProcessInfo.processInfo.environment["FRONTIER_ARTICLE_FIXTURE"] {
                        var saved = try JSONDecoder().decode(FormattedArticle.self, from: Data(contentsOf: URL(fileURLWithPath: fixture)))
                        saved.originalFile = material.originalFile
                        try JSONEncoder().encode(saved).write(to: MaterialStore.live.directory(material.id).appendingPathComponent("formatted-article.json"), options: .atomic)
                    }
                    model.materials = [material]; model.readingMaterialID = material.id
                    model.readingMode = articlePreview || fallbackPreview ? .learn : CommandLine.arguments.contains("--preview-compare") ? .compare : .source
                }
                let view = NSHostingView(rootView: content.environment(\.colorScheme, CommandLine.arguments.contains("--dark") ? .dark : .light).background(Color(nsColor: .windowBackgroundColor)))
                let window = NSWindow(contentRect: NSRect(x: 160, y: 140, width: 1040, height: 720),
                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.title = "Frontier · synthetic reader check"
                window.titlebarAppearsTransparent = true
                window.backgroundColor = NSColor(LibraryTheme.paper)
                window.contentView = view
                if panel { window.setContentSize(view.fittingSize) }
                window.makeKeyAndOrderFront(nil)
                if CommandLine.arguments.contains("--preview-discussion") {
                    let fake = FileManager.default.temporaryDirectory.appendingPathComponent("frontier-preview-ai")
                    try "#!/bin/sh\ncat >/dev/null\nprintf 'Consider the assumption carefully: $x^2$. What evidence supports it?'\n".write(to: fake, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
                    var settings = AISettings(); settings.executablePath = fake.path
                    model.showingDiscussion = true
                    let chat = model.discussion(for: model.discussionID)
                    await chat.send("Is my interpretation correct?", source: { "Test source" }, settings: { settings })
                    try await Task.sleep(for: .milliseconds(1200))
                    guard webViews(view).count >= 2 else { throw FrontierError("Discussion did not open next to reading") }
                    try capture(view, to: destination)
                    model.showingDiscussion = false
                    try await Task.sleep(for: .milliseconds(100))
                    model.showingDiscussion = true
                    guard model.discussion(for: model.discussionID).messages.count == 2 else { throw FrontierError("Closing discussion lost history") }
                    print("PASS discussion opens alongside reading, renders its answer and preserves history when collapsed")
                    exit(0)
                }
                if fallbackPreview {
                    for _ in 0..<150 {
                        if accessibilityElement(view, id: "pdf-next") != nil { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard accessibilityElement(view, id: "pdf-next") != nil else { throw FrontierError("Unformatted paper did not open its original") }
                    try capture(view, to: destination)
                    guard let walk = accessibilityElement(view, id: "reading-mode-walkthrough"), press(walk) else { throw FrontierError("Walkthrough unavailable") }
                    try await Task.sleep(for: .milliseconds(200))
                    guard accessibilityElement(view, id: "material-learning-start") != nil else { throw FrontierError("Guided teaching was not retained") }
                    guard let read = accessibilityElement(view, id: "reading-mode-read"), press(read) else { throw FrontierError("Return to Read unavailable") }
                    try await Task.sleep(for: .milliseconds(300))
                    guard accessibilityElement(view, id: "pdf-next") != nil else { throw FrontierError("Return to reading failed") }
                    print("PASS original reading by default, explicit guided teaching, return to original")
                    exit(0)
                }
                if articlePreview {
                    var articleWeb: WKWebView?
                    for _ in 0..<400 {
                        articleWeb = webViews(view).first { $0.url?.lastPathComponent == "article.html" }
                        if let articleWeb, !articleWeb.isHidden, ((try? await articleWeb.evaluateJavaScript("document.querySelectorAll('#article math').length")) as? Int ?? 0) > 100 { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard let articleWeb else { throw FrontierError("No formatted article renderer.") }
                    let metrics = try await articleWeb.evaluateJavaScript("({math:document.querySelectorAll('math').length, fractions:document.querySelectorAll('mfrac').length, figures:document.querySelectorAll('figure').length, svg:document.querySelectorAll('svg').length, images:[...document.images].filter(i=>i.naturalWidth>0).length})")
                    print("Formatted article: \(metrics)")
                    guard ((try await articleWeb.evaluateJavaScript("document.querySelectorAll('math').length")) as? Int ?? 0) > 100 else { throw FrontierError("The article lost mathematical structure.") }
                    if CommandLine.arguments.contains("--check-article-notes") {
                        try await ArticleReadingChecks.run(web: articleWeb, view: view, model: model)
                        try await Task.sleep(for: .milliseconds(300))
                        try capture(view, to: destination)
                        let image = try await articleWeb.takeSnapshot(configuration: nil)
                        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
                            try data.write(to: destination.deletingPathExtension().appendingPathExtension("web.png"))
                        }
                        let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        capture.arguments = ["-x", "-l", String(window.windowNumber), destination.deletingPathExtension().appendingPathExtension("window.png").path]
                        try? capture.run(); capture.waitUntilExit()
                        print("PASS formatted reading annotations captured; web bounds \(articleWeb.bounds)")
                        exit(0)
                    }
                    _ = try await articleWeb.evaluateJavaScript("document.getElementById('S2').scrollIntoView()")
                    try await Task.sleep(for: .milliseconds(300))
                    try capture(view, to: destination)
                    let before = articleWeb.bounds.width
                    guard let toggle = accessibilityElement(view, id: "toggle-sidebar"), press(toggle) else { throw FrontierError("Sidebar toggle did not respond.") }
                    try await Task.sleep(for: .milliseconds(400))
                    guard articleWeb.bounds.width > before + 200 else { throw FrontierError("Collapsing sidebar did not expand the reader.") }
                    _ = try await articleWeb.evaluateJavaScript("document.querySelector('figure').scrollIntoView()")
                    try await Task.sleep(for: .milliseconds(200))
                    try capture(view, to: destination.deletingPathExtension().appendingPathExtension("figure.png"))
                    guard let show = accessibilityElement(view, id: "toggle-sidebar"), press(show) else { throw FrontierError("Sidebar could not reopen.") }
                    model.readingMode = .compare
                    try await Task.sleep(for: .milliseconds(1000))
                    try capture(view, to: destination.deletingPathExtension().appendingPathExtension("compare.png"))
                    print("PASS structured math and figures, sidebar collapse/reopen, cached side-by-side reading")
                    exit(0)
                }
                if sourcePreview {
                    print("Source UI mounted")
                    try await Task.sleep(for: .milliseconds(1500))
                    print("Source UI settled")
                    guard let item = model.activeMaterial, let source = model.pdfReader(for: item), source.pageCount > 1 else { throw FrontierError("Source reader did not load the PDF.") }
                    guard let next = accessibilityElement(view, id: "pdf-next"), press(next) else { throw FrontierError("The next-page button did not respond.") }
                    try await Task.sleep(for: .milliseconds(200))
                    guard source.pageNumber == 2 else { throw FrontierError("PDF page navigation failed.") }
                    source.find(ProcessInfo.processInfo.environment["PDF_SEARCH"] ?? "decoding")
                    guard source.hasSelection else { throw FrontierError("PDF search did not select matching text.") }
                    try await Task.sleep(for: .milliseconds(100))
                    source.highlightColor = .red
                    guard accessibilityElement(view, id: "pdf-highlight-color") != nil else { throw FrontierError("Highlight color control missing") }
                    guard let highlight = accessibilityElement(view, id: "pdf-highlight"), press(highlight) else { throw FrontierError("The highlight button did not respond.") }
                    source.save()
                    guard !source.dirty, !source.annotations.isEmpty else { throw FrontierError("PDF highlight did not save.") }
                    try await Task.sleep(for: .milliseconds(300))
                    guard view.bounds.height <= 721 else { throw FrontierError("Source reader expanded beyond the window.") }
                    try capture(view, to: destination)
                    guard source.noteTarget != nil else { throw FrontierError("Highlight lost its note target") }
                    guard let add = accessibilityElement(view, id: "pdf-add-note"), press(add) else { throw FrontierError("Highlight → Add note did not open") }
                    try await Task.sleep(for: .milliseconds(100))
                    guard accessibilityElement(view, id: "pdf-note-editor") != nil else { throw FrontierError("Anchored note composer missing") }
                    guard let cancel = accessibilityElement(view, id: "pdf-cancel-note"), press(cancel) else { throw FrontierError("Anchored composer could not close") }
                    model.handleSourceURL(URL(string: "frontier://source/" + item.id + "?page=2")!)
                    try await Task.sleep(for: .milliseconds(100))
                    guard model.screen == .read, model.readingMode == .source, source.pageNumber == 2 else { throw FrontierError("Source deep link did not restore its page.") }
                    guard let first = source.annotations.first else { throw FrontierError("No highlight to test") }
                    if CommandLine.arguments.contains("--preview-margins") {
                        source.edit(first, text: "Does this result hold when the assumptions change? I want to compare the evidence before accepting the claim.")
                        source.find("framework")
                        source.highlightColor = .green
                        source.addNote("Connect this explanation to the earlier section on decoding.")
                        source.save(); source.reveal(first)
                        try await Task.sleep(for: .milliseconds(250))
                        try capture(view, to: destination.deletingPathExtension().appendingPathExtension("margins.png"))
                        guard let edit = accessibilityElement(view, id: "pdf-edit-" + first.stableID), press(edit) else { throw FrontierError("Margin Edit did not respond") }
                        try await Task.sleep(for: .milliseconds(200))
                        try capture(view, to: destination.deletingPathExtension().appendingPathExtension("editor.png"))
                        guard accessibilityElement(view, id: "pdf-keep-note") != nil else { throw FrontierError("Inline note editor did not open") }
                        guard let keep = accessibilityElement(view, id: "pdf-keep-note"), press(keep) else { throw FrontierError("Keep note did not respond") }
                        for _ in 0..<100 {
                            if source.noteDraft == nil && !source.savingNote { break }
                            try await Task.sleep(for: .milliseconds(50))
                        }
                        try await Task.sleep(for: .milliseconds(100))
                        guard source.noteDraft == nil, accessibilityElement(view, id: "pdf-keep-note") == nil else {
                            throw FrontierError("Editor did not close after keeping note: " + (source.error ?? source.draftError ?? "save did not finish"))
                        }
                        guard let add = accessibilityElement(view, id: "pdf-add-note"), press(add) else { throw FrontierError("Add note did not open") }
                        try await Task.sleep(for: .milliseconds(100))
                        guard let cancel = accessibilityElement(view, id: "pdf-cancel-note"), press(cancel) else { throw FrontierError("Cancel note did not respond") }
                        guard let toggle = accessibilityElement(view, id: "pdf-toggle-notes"), press(toggle) else { throw FrontierError("Notes toggle did not close") }
                        try await Task.sleep(for: .milliseconds(100))
                        source.focusedAnnotation = first
                        try await Task.sleep(for: .milliseconds(100))
                        guard accessibilityElement(view, id: "pdf-margin-panel") != nil else { throw FrontierError("Annotation focus did not reopen margins") }
                        print("PASS margin Edit/Keep, Add/Cancel, and panel close/reopen via native buttons")
                        source.beginNote(first)
                        source.noteDraft?.text = "A thought that must follow this passage"
                        let savedDraft = source.noteDraft
                        let other = try MaterialStore.live.add(Resource.document(Data(contentsOf: source.original), filename: "other.pdf", origin: "isolated-second-document"))
                        model.materials.append(other); model.readingMaterialID = other.id
                        try await Task.sleep(for: .milliseconds(250))
                        guard let otherSource = model.pdfReader(for: other), otherSource !== source,
                              otherSource.view.window != nil, source.view.window == nil,
                              otherSource.noteDraft == nil else { throw FrontierError("Switching PDFs retained the previous document or its editor") }
                        model.readingMaterialID = item.id
                        try await Task.sleep(for: .milliseconds(250))
                        guard source.view.window != nil, source.noteDraft == savedDraft,
                              accessibilityElement(view, id: "pdf-note-editor") != nil else { throw FrontierError("Returning to PDF lost its anchored draft") }
                        let reopenedDraft = SourcePDF(original: source.original, annotated: source.annotated)
                        guard reopenedDraft.noteDraft == savedDraft else { throw FrontierError("Anchored draft was not saved for restart") }
                        source.go(to: 2)
                        guard model.discussionContext.contains("[PDF page 2 — current page]") else { throw FrontierError("Discussion did not follow source navigation") }
                        guard await source.commitNoteDraft() else { throw FrontierError("Restored note draft could not save") }
                        guard SourcePDF(original: source.original, annotated: source.annotated).annotations.contains(where: { $0.contents == "A thought that must follow this passage" }) else { throw FrontierError("Restored draft failed annotation round trip") }
                        print("PASS switching PDFs replaces the native document, retains separate drafts, restores composer and uses current page for discussion")

                    }
                    source.reveal(first)
                    try await Task.sleep(for: .milliseconds(100))
                    source.view.refreshMargin()
                    guard let bubble = source.view.subviews.compactMap({ $0 as? NSButton }).first else { throw FrontierError("No clickable margin bubble") }
                    source.focusedAnnotation = nil; bubble.performClick(nil)
                    guard source.focusedAnnotation != nil else { throw FrontierError("Margin bubble did not open its annotation") }
                    let began = Date(); source.addNote("Native regression note")
                    let addMS = Date().timeIntervalSince(began) * 1000
                    guard let note = source.annotations.first(where: { $0.contents == "Native regression note" }) else { throw FrontierError("Note not added") }
                    let removedAt = Date(); source.remove(note)
                    let removeMS = Date().timeIntervalSince(removedAt) * 1000
                    guard !source.annotations.contains(where: { $0.contents == "Native regression note" }) else { throw FrontierError("Removed note is still in the list") }
                    for _ in 0..<300 { if !source.dirty { break }; try await Task.sleep(for: .milliseconds(100)) }
                    guard !source.dirty else { throw FrontierError("Background annotation save did not complete") }
                    let reopened = SourcePDF(original: source.original, annotated: source.annotated)
                    guard !reopened.annotations.contains(where: { $0.contents == "Native regression note" }) else { throw FrontierError("Deleted note reappeared on disk") }
                    try capture(view, to: destination)
                    print("PASS native margin bubble, add/remove note, background save and reopen; add \(Int(addMS)) ms, remove \(Int(removeMS)) ms")
                    print("PASS source PDF navigation, search, highlight save and bounded layout")
                    exit(0)
                }
                if navigation {
                    try await checkNavigation(model: model, view: view)
                    try capture(view, to: destination)
                    window.orderOut(nil)
                    exit(0)
                }
                if panel || library || unwritten || graph {
                    try await Task.sleep(for: .milliseconds(graph ? 1500 : 500))
                    if graph && CommandLine.arguments.contains("--preview-graph-focus") {
                        guard model.graphFocus == nil else { throw FrontierError("Reading selection leaked into graph focus.") }
                        for id in ["node-1", "node-2", "node-1"] {
                            model.graphFocus = id
                            try await Task.sleep(for: .milliseconds(150))
                            guard let card = webViews(view).first, (try await card.evaluateJavaScript("document.querySelector('#out h1')?.textContent")) as? String == (id == "node-1" ? "Geometry: x2+y2" : "Concept 2") else { throw FrontierError("Graph focus did not update its preview.") }
                        }
                        model.graphFocus = nil
                        guard model.selected == "node-0" else { throw FrontierError("Hover changed the reading selection.") }
                        model.selectGraphConcept("node-2")
                        guard model.selected == "node-2", model.screen == .graph else { throw FrontierError("Explicit graph selection did not choose the reading target.") }
                        print("PASS graph starts unfocused, preview follows focus, clearing focus preserves reading selection")
                        try capture(view, to: destination); exit(0)
                    }
                    if graph {
                        guard let card = webViews(view).first,
                              (try await card.evaluateJavaScript("document.querySelectorAll('#out .katex').length")) as? Int == 2 else {
                            throw FrontierError("Graph hover preview did not typeset title and relevance math.")
                        }
                        print("PASS graph hover card renders title and relevance with KaTeX")
                    }
                    if unwritten {
                        var intro: WKWebView?
                        for _ in 0..<100 {
                            intro = webViews(view).first
                            if let intro, (try? await intro.evaluateJavaScript("document.querySelectorAll('#out em .katex').length")) as? Int == 1 { break }
                            try await Task.sleep(for: .milliseconds(100))
                        }
                        _ = try await intro?.callAsyncJavaScript("await document.fonts.ready; return true", arguments: [:], in: nil, contentWorld: .page)
                        try await Task.sleep(for: .milliseconds(400))
                        guard view.bounds.height <= 721 else { throw FrontierError("The introduction expanded the window beyond its requested height: \(view.bounds.height).") }
                        guard let intro,
                              (try await intro.evaluateJavaScript("document.querySelectorAll('#out em .katex').length")) as? Int == 1 else {
                            throw FrontierError("The introduction must retain italic text and typeset math.")
                        }
                        var ancestor = intro.superview
                        while ancestor != nil && !(ancestor is NSScrollView) { ancestor = ancestor?.superview }
                        guard let scroll = ancestor as? NSScrollView, let document = scroll.documentView else {
                            throw FrontierError("The introduction and action must share a native scroll view.")
                        }
                        let measured = try await intro.evaluateJavaScript("document.getElementById('out').getBoundingClientRect().bottom + 24") as? Double ?? 0
                        guard abs(intro.bounds.height - measured) < 2 else {
                            throw FrontierError("Introduction height does not match its content: \(intro.bounds.height) vs \(measured).")
                        }
                        guard document.bounds.height - intro.bounds.height < 290 else {
                            throw FrontierError("The action area is separated from the introduction by excess empty space.")
                        }
                        let end = max(0, document.bounds.height - scroll.contentView.bounds.height)
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: end))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        try await Task.sleep(for: .milliseconds(150))
                        let metricBottom = try await intro.evaluateJavaScript("document.querySelector('#out .katex').getBoundingClientRect().bottom") as? Double ?? 0
                        let metric = intro.convert(NSRect(x: 0, y: metricBottom - 20, width: 10, height: 20), to: document)
                        guard scroll.documentVisibleRect.intersects(metric) else { throw FrontierError("The final equation cannot be reached by scrolling.") }
                        if !CommandLine.arguments.contains("--short") && end <= 0 { throw FrontierError("Long content did not produce a scrolling document.") }
                        print("PASS italic math, natural action spacing, reachable last equation and bounded window")
                        print("Introduction height: \(intro.bounds.height); document: \(document.bounds.height); viewport: \(scroll.contentView.bounds.height)")
                        try capture(view, to: destination.deletingPathExtension().appendingPathExtension("scrolled.png"))
                        scroll.contentView.scroll(to: .zero)
                        scroll.reflectScrolledClipView(scroll.contentView)
                        try await Task.sleep(for: .milliseconds(100))
                        try capture(view, to: destination)
                        if let frameView = view.superview {
                            try capture(frameView, to: destination.deletingPathExtension().appendingPathExtension("window.png"))
                        }
                        let previousHeight = intro.bounds.height
                        window.setContentSize(NSSize(width: 860, height: 720))
                        try await Task.sleep(for: .milliseconds(500))
                        guard view.bounds.height <= 721, intro.bounds.height > previousHeight else {
                            throw FrontierError("Introduction did not reflow into its narrower viewport.")
                        }
                        print("PASS introduction remeasures when window width changes")
                        try capture(view, to: destination.deletingPathExtension().appendingPathExtension("narrow.png"))
                        window.orderOut(nil)
                        exit(0)
                    }
                    try capture(view, to: destination)
                    if library {
                        window.setContentSize(NSSize(width: 820, height: 680))
                        try await Task.sleep(for: .milliseconds(400))
                        try capture(view, to: destination.deletingPathExtension().appendingPathExtension("narrow.png"))
                    }
                    if CommandLine.arguments.contains("--preview-actual-covers") {
                        let before = model.coverDesigns
                        let extra = LibraryMaterial(id: "preview-added-material", title: "A new paper: questions, evidence and discovery", kind: .paper, format: "PDF")
                        model.materials.append(extra)
                        guard before.allSatisfy({ model.coverDesigns[$0.key] == $0.value }),
                              let allocated = model.coverDesigns[extra.id], !before.values.contains(allocated) else {
                            throw FrontierError("Adding a paper reused a composition or changed an existing cover")
                        }
                        window.setContentSize(NSSize(width: 1040, height: 720))
                        try await Task.sleep(for: .milliseconds(500))
                        try capture(view, to: destination.deletingPathExtension().appendingPathExtension("new-item.png"))
                        print("PASS actual-library covers remain stable when a new material receives its own composition")
                    }
                    window.orderOut(nil)
                    exit(0)
                }
                var web: WKWebView?
                for _ in 0..<100 {
                    try await Task.sleep(for: .milliseconds(100))
                    web = webViews(view).first
                    if let web, (try? await web.evaluateJavaScript("document.querySelectorAll('.katex').length")) as? Int == 2 { break }
                }
                guard let web else { throw NSError(domain: "No reader web view", code: 1) }
                guard web.bounds.height > 100, web.bounds.height < window.frame.height,
                      (try await web.evaluateJavaScript("document.querySelectorAll('.katex').length")) as? Int == 2 else {
                    throw FrontierError("Reader layout or math rendering failed.")
                }
                _ = try await web.evaluateJavaScript("window.scrollTo(0, 220)")
                model.screen = .library
                try await Task.sleep(for: .milliseconds(150))
                model.screen = .read
                try await Task.sleep(for: .milliseconds(150))
                guard webViews(view).first === web,
                      (try await web.evaluateJavaScript("window.scrollY")) as? Int == 220 else {
                    throw FrontierError("Tab switching recreated the reader or reset its reading position.")
                }
                print("PASS switching Library/Read retains the same web view and scroll position")
                _ = try await web.evaluateJavaScript("window.scrollTo(0, 0)")
                window.setContentSize(NSSize(width: 1160, height: 800))
                try await Task.sleep(for: .milliseconds(300))
                guard web.bounds.width > 800, web.bounds.height < 800 else { throw FrontierError("Reader failed to resize with the window.") }
                print("PASS reader stays bounded and resizes with the window")
                let metrics = try await web.evaluateJavaScript("JSON.stringify({text:document.getElementById('out').innerText.length,math:document.querySelectorAll('.katex').length,height:innerHeight,scroll:document.documentElement.scrollHeight})")
                print("Reader DOM: \(String(describing: metrics))")
                print("Reader frame: \(web.frame); window: \(window.windowNumber)")
                _ = try await web.callAsyncJavaScript("await document.fonts.ready; return true", arguments: [:], in: nil, contentWorld: .page)
                try await Task.sleep(for: .milliseconds(500))
                let snapshot = try await web.takeSnapshot(configuration: nil)
                if let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                   let data = bitmap.representation(using: .png, properties: [:]) {
                    try data.write(to: destination.deletingPathExtension().appendingPathExtension("web.png"))
                }
                try capture(view, to: destination)
                print("Saved hosted-view and WebKit screenshots.")
                // Simulate a renderer exception, then verify readable native fallback.
                _ = try await web.evaluateJavaScript("window.renderMarkdown = undefined")
                model.concepts[0].body += "\n\nA changed document."
                try await Task.sleep(for: .milliseconds(300))
                guard let container = web.superview as? WebPane.FillContainer,
                      !container.fallback.isHidden, container.source.string.contains("A changed document") else {
                    throw FrontierError("Reader failure did not show readable fallback text.")
                }
                print("PASS rendering failure shows readable native text")
                web.reload()
                for _ in 0..<100 {
                    try await Task.sleep(for: .milliseconds(100))
                    if container.fallback.isHidden { break }
                }
                guard container.fallback.isHidden else { throw FrontierError("Reader did not recover after reload.") }
                print("PASS reader recovers after reload")
                window.orderOut(nil)
                exit(0)
            } catch { print("Reader preview failed: \(error)"); exit(1) }
        }
        RunLoop.main.run()
        fatalError("Preview unexpectedly stopped")
    }
}

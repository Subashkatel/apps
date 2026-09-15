import LocalSupport
import Foundation

enum ImportTests {
    static func run(_ check: (String, Bool, String) -> Void) {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("frontier-import-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        func verify(_ name: String, _ ok: Bool) { check(name, ok, "") }
        func rejects(_ action: () throws -> Void) -> Bool { do { try action(); return false } catch { return true } }
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            func file(_ name: String, _ text: String) throws -> URL {
                let url = scratch.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
                return url
            }
            let md = try file("course.md", "# First\n\nProbability $p_i$.\n\n# Second\n\nMore text.")
            let markdown = try Resource.read(md.path)
            verify("Markdown imports preserve headings and equations", markdown.sections.map(\.title) == ["First", "Second"] && markdown.sections[0].text.contains("$p_i$"))
            let txt = try file("notes.txt", "A short but valid note.")
            verify("short plain text imports are not discarded", try Resource.read(txt.path).sections[0].text == "A short but valid note.")
            let html = try file("page.html", "<html><head><title>Lesson</title></head><body><p>Brief content.</p><script>UNWANTED()</script></body></html>")
            let page = try Resource.read(html.path)
            verify("local HTML extracts text without scripts", page.sections[0].text.contains("Brief content") && !page.sections[0].text.contains("UNWANTED"))
            let tex = try file("latex/main.tex", #"\section{Start}"# + "\n" + #"A formula: $\frac{a_b}{c}$.\input{part}"#)
            _ = try file("latex/part.tex", #"\section{Next} More mathematics: \[x^2\]."#)
            let latex = try Resource.read(tex.path)
            verify("LaTeX includes expand in order and math survives", latex.sections.map(\.title) == ["Start", "Next"] && latex.sections[0].text.contains(#"\frac{a_b}{c}"#))
            let cycle = try file("latex/cycle.tex", #"\input{cycle}"#)
            verify("LaTeX include cycles fail clearly", rejects { _ = try Resource.read(cycle.path) })
            let escape = try file("latex/escape.tex", #"\input{../notes.txt}"#)
            verify("LaTeX imports cannot read outside their source directory", rejects { _ = try Resource.read(escape.path) })
            let rtf = try file("note.rtf", #"{\rtf1\ansi Hello \b reader\b0 .}"#)
            verify("RTF imports readable text", try Resource.read(rtf.path).sections[0].text.contains("reader"))
            let utf16 = scratch.appendingPathComponent("unicode.txt")
            try "Probability π".data(using: .utf16)!.write(to: utf16)
            verify("UTF-16 text is decoded", try Resource.read(utf16.path).sections[0].text.contains("π"))
            let unknown = try file("unknown.xyz", "text")
            verify("unsupported formats fail explicitly", rejects { _ = try Resource.read(unknown.path) })

            // Archive order deliberately differs from the book's spine.
            _ = try file("epub/META-INF/container.xml", #"<?xml version="1.0"?><container><rootfiles><rootfile full-path="Book/content.opf"/></rootfiles></container>"#)
            _ = try file("epub/Book/content.opf", #"<?xml version="1.0"?><package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>Test Book</dc:title></metadata><manifest><item id="one" href="z.xhtml" media-type="application/xhtml+xml"/><item id="two" href="a.xhtml" media-type="application/xhtml+xml"/><item id="skip" href="skip.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/><itemref idref="skip" linear="no"/><itemref idref="two"/></spine></package>"#)
            _ = try file("epub/Book/z.xhtml", "<html><head><title>First chapter</title></head><body><p>First reading text.</p></body></html>")
            _ = try file("epub/Book/a.xhtml", "<html><head><title>Second chapter</title></head><body><p>Second reading text.</p></body></html>")
            let epub = scratch.appendingPathComponent("book.epub")
            _ = try LocalProcess.run(URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-qr", epub.path, "."], directory: scratch.appendingPathComponent("epub"))
            let book = try Resource.read(epub.path)
            verify("EPUB follows spine order and skips non-linear entries", book.name == "Test Book" && book.sections.map(\.title) == ["First chapter", "Second chapter"])
            let archive = try BookArchive(epub)
            verify("EPUB chapter paths cannot escape the archive", rejects { _ = try archive.resolve("../../outside", relativeTo: "Book/content.opf") })
            _ = try file("docx/word/document.xml", #"<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Chapter One</w:t></w:r></w:p><w:p><w:r><w:t>Readable Word document.</w:t></w:r></w:p></w:body></w:document>"#)
            let docx = scratch.appendingPathComponent("book.docx")
            _ = try LocalProcess.run(URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-qr", docx.path, "."], directory: scratch.appendingPathComponent("docx"))
            let word = try Resource.read(docx.path)
            verify("DOCX preserves heading and paragraph text", word.sections[0].title == "Chapter One" && word.sections[0].text.contains("Readable Word"))
            let long = Resource.batches([.init(title: "Dense", text: String(repeating: "α", count: 100_001))], cap: 1000)
            verify("one long paragraph cannot exceed an AI batch limit", long.count == 101 && long.allSatisfy { $0.reduce(0) { $0 + $1.text.count } <= 1000 })

            let settingsURL = scratch.appendingPathComponent("ai.json")
            verify("AI defaults to the existing Claude setup", try AISettings.load(from: settingsURL).provider == .claude)
            var settings = AISettings()
            settings.provider = .server; settings.endpoint = "http://localhost:1234/v1/"; settings.serverModel = "my-model"
            try settings.save(to: settingsURL)
            verify("AI selection and model survive restart", try AISettings.load(from: settingsURL) == settings)
            verify("server API URL is normalized once", try settings.serverURL().absoluteString == "http://localhost:1234/v1/chat/completions")
            settings.endpoint = "https://example.invalid/v1/chat/completions"
            verify("full chat endpoint is accepted without duplication", try settings.serverURL().absoluteString == settings.endpoint)
            let request = try AIClient.request(settings: settings, prompt: "synthetic prompt", key: "synthetic-key", timeout: 30)
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            verify("custom server receives the chosen model and prompt", body["model"] as? String == "my-model" && request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key")
            let saved = try String(contentsOf: settingsURL)
            verify("API keys do not enter settings JSON", !saved.contains("synthetic-key"))
            verify("server errors cannot masquerade as generated text", rejects { _ = try AIClient.response(Data(), status: 401) })
            let response = Data(#"{"choices":[{"message":{"content":"A lesson"},"finish_reason":"stop"}]}"#.utf8)
            verify("chat completion response is decoded", try AIClient.response(response, status: 200) == "A lesson")
            settings.endpoint = "https://name:secret@example.invalid/v1"
            verify("credentials embedded in endpoint URLs are rejected", rejects { _ = try settings.serverURL() })
            verify("custom model label matches the model sent", settings.selectionLabel == "Custom server · my-model")
            var automatic = AISettings()
            for provider in [AIProvider.claude, .codex, .gemini] {
                automatic.provider = provider
                verify("\(provider.title) default model is explicit rather than guessed", automatic.modelLabel == "CLI default")
            }
            let legacyMessage = try JSONDecoder().decode(DiscussionMessage.self, from: Data("{\"role\":\"assistant\",\"text\":\"Earlier reply\",\"provider\":\"Claude\"}".utf8))
            verify("old conversations remain readable without model metadata", legacyMessage.model == nil)
            settings.provider = .codex; settings.codexModel = "chosen-model"
            let codexArgs = settings.arguments()
            verify("Codex uses noninteractive read-only execution and selected model", codexArgs.contains("read-only") && codexArgs.contains("chosen-model") && codexArgs.contains("--ephemeral"))
            settings.provider = .claude
            let claudeArgs = settings.arguments()
            verify("Claude generation disables tools and session persistence", claudeArgs.contains("--tools") && claudeArgs.contains("") && claudeArgs.contains("--no-session-persistence"))
            let echoed = try LocalProcess.run(URL(fileURLWithPath: "/bin/cat"), arguments: [], input: Data(repeating: 65, count: 200_000))
            verify("large subprocess input and output cannot deadlock pipes", echoed.count == 200_000)
            verify("subprocess nonzero exit is reported", rejects { _ = try LocalProcess.run(URL(fileURLWithPath: "/usr/bin/false"), arguments: []) })
            verify("subprocess output limit is enforced", rejects { _ = try LocalProcess.run(URL(fileURLWithPath: "/bin/cat"), arguments: [], input: Data(repeating: 65, count: 2000), limit: 100) })
        } catch { check("new import and AI checks", false, error.localizedDescription) }
    }
}

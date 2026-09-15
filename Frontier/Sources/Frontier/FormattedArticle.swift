import AppKit
import SwiftUI
import WebKit
import PDFKit

struct FormattedArticle: Codable {
    let html: String
    let source: URL
    var originalFile: String? = nil
    static func sourceURL(origin: String, original: URL?) -> URL? {
        let page = original.flatMap { PDFDocument(url: $0)?.page(at: 0)?.string } ?? ""
        let stamp = try? NSRegularExpression(pattern: #"arXiv:\s*(\d{4}\.\d{4,5}(?:v\d+)?)"#, options: .caseInsensitive)
        let match = stamp?.firstMatch(in: page, range: NSRange(page.startIndex..., in: page))
        let stampedID = match.flatMap { Range($0.range(at: 1), in: page) }.map { String(page[$0]) }
        let originID = URL(string: origin).flatMap(Resource.arxivID)
        guard var id = originID ?? stampedID else { return nil }
        // Match the attached PDF's version, rather than silently reading a newer revision.
        if let stampedID, stampedID.components(separatedBy: "v")[0] == id.components(separatedBy: "v")[0] { id = stampedID }

        return URL(string: "https://arxiv.org/html/" + id)
    }
    static func fetch(_ url: URL) async throws -> Self {
        var request = URLRequest(url: url); request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              data.count < 15_000_000, let page = String(data: data, encoding: .utf8),
              let start = page.range(of: "<article"), let end = page.range(of: "</article>", options: .backwards), start.lowerBound < end.upperBound else {
            throw FrontierError("A formatted version is not available for this paper. The original PDF remains readable.")
        }
        var article = String(page[start.lowerBound..<end.upperBound])
        // Cache article figures; inline SVG and MathML already travel with the HTML.
        let pattern = try NSRegularExpression(pattern: #"<(?:img|object)\b[^>]*\b(?:src|data)\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive)
        let matches = pattern.matches(in: article, range: NSRange(article.startIndex..., in: article))
        let references = Set(matches.compactMap { Range($0.range(at: 1), in: article).map { String(article[$0]) } })
        guard references.count <= 100 else { throw FrontierError("This article contains too many images to cache.") }
        var total = data.count
        for reference in references where !reference.hasPrefix("data:") {
            guard let asset = URL(string: reference, relativeTo: response.url ?? url)?.absoluteURL,
                  asset.scheme == "https", asset.host == url.host else { continue }
            var imageRequest = URLRequest(url: asset); imageRequest.timeoutInterval = 20
            let (bytes, reply) = try await URLSession.shared.data(for: imageRequest)
            guard let reply = reply as? HTTPURLResponse, reply.statusCode == 200,
                  ["image/png", "image/jpeg", "image/svg+xml", "image/webp", "image/gif"].contains(reply.mimeType ?? ""), bytes.count <= 20_000_000 else {
                throw FrontierError("A figure could not be downloaded. Use the original PDF or retry the formatted view.")
            }
            total += bytes.count
            guard total <= 60_000_000 else { throw FrontierError("The formatted article is too large to cache.") }
            article = article.replacingOccurrences(of: reference, with: "data:" + (reply.mimeType ?? "image/png") + ";base64," + bytes.base64EncodedString())
        }
        return Self(html: article, source: response.url ?? url)
    }
}

struct FormattedMaterialReader: View {
    @ObservedObject var model: Model
    let material: LibraryMaterial
    @State private var article: FormattedArticle?
    @State private var error: String?
    @State private var loading = true
    @State private var retry = 0
    private var original: URL? { MaterialStore.live.existingOriginal(material) }
    private var cache: URL { MaterialStore.live.directory(material.id).appendingPathComponent("formatted-article.json") }
    var body: some View {
        VStack(spacing: 0) {
            if let article {
                HStack {
                    Text("Formatted paper · saved on this Mac").font(.caption).foregroundStyle(LibraryTheme.muted)
                    Spacer(); Link("arXiv ↗", destination: article.source).font(.caption)
                }.padding(12)
                if let source = model.pdfReader(for: material) {
                    AnnotatedArticleReader(article: article, positionURL: cache.appendingPathExtension("position.json"), source: source,
                        openOriginal: { model.readingMode = .source }, explain: { model.explainArticlePassage($0, material: material) },
                        contextChanged: { model.articleContexts[material.id] = $0 })
                } else { ArticlePane(article: article, positionURL: cache.appendingPathExtension("position.json")) }
            } else {
                if loading { HStack { ProgressView().controlSize(.small); Text("Preparing the formatted paper…").font(.caption) }.padding(12) }
                if let error { HStack { Text(error).font(.caption); Button("Retry") { retry += 1 } }.padding(12) }
                if !loading { MaterialSource(model: model, item: material) }
                else { Spacer() }
            }
        }.task(id: "\(material.id)-\(retry)") {
            article = nil; error = nil; loading = true
            defer { loading = false }
            if let saved = try? Data(contentsOf: cache), let decoded = try? JSONDecoder().decode(FormattedArticle.self, from: saved), decoded.originalFile == material.originalFile { article = decoded; return }
            let origin = material.origin, original = original
            guard let url = await Task.detached(operation: { FormattedArticle.sourceURL(origin: origin, original: original) }).value else { return }
            do {
                var result = try await FormattedArticle.fetch(url)
                result.originalFile = material.originalFile
                try Task.checkCancellation()
                try JSONEncoder().encode(result).write(to: cache, options: .atomic)
                article = result
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

struct ArticlePane: NSViewRepresentable {
    let article: FormattedArticle
    var positionURL: URL? = nil
    var marks: [[String: Any]] = []
    var revealID: String? = nil
    var revealRequest = 0
    var revealUnavailable: () -> Void = {}
    var selectionChanged: (String) -> Void = { _ in }
    var noteClicked: (String) -> Void = { _ in }
    var contextChanged: (String) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WebPane.FillContainer {
        let container = WebPane.FillContainer(frame: .zero)
        context.coordinator.container = container
        context.coordinator.positionURL = positionURL
        container.web.configuration.userContentController.add(context.coordinator, name: "articlePosition")
        container.web.configuration.userContentController.add(context.coordinator, name: "articleNotes")
        container.web.navigationDelegate = context.coordinator
        container.web.allowsMagnification = true
        context.coordinator.article = article
        if let url = Bundle.main.url(forResource: "article", withExtension: "html", subdirectory: "web") {
            container.web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { container.showSource("The formatted reader is missing. Open Source to read the PDF.") }
        return container
    }
    func updateNSView(_ view: WebPane.FillContainer, context: Context) {
        context.coordinator.article = article
        context.coordinator.marks = marks; context.coordinator.selectionChanged = selectionChanged
        context.coordinator.noteClicked = noteClicked; context.coordinator.contextChanged = contextChanged
        context.coordinator.revealRequest = revealRequest; context.coordinator.revealUnavailable = revealUnavailable
        context.coordinator.requestedReveal = revealID; context.coordinator.render()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WebPane.FillContainer, context: Context) -> CGSize? { CGSize(width: proposal.width ?? 400, height: proposal.height ?? 500) }
    static func dismantleNSView(_ nsView: WebPane.FillContainer, coordinator: Coordinator) {
        nsView.web.configuration.userContentController.removeScriptMessageHandler(forName: "articlePosition")
        nsView.web.configuration.userContentController.removeScriptMessageHandler(forName: "articleNotes")
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var positionURL: URL?
        var marks: [[String: Any]] = []
        var selectionChanged: (String) -> Void = { _ in }
        var noteClicked: (String) -> Void = { _ in }
        var contextChanged: (String) -> Void = { _ in }
        var requestedReveal: String?
        var revealRequest = 0, lastRevealRequest = 0
        var revealUnavailable: () -> Void = {}
        var lastMarks = ""
        var articleReady = false
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let data = message.body as? [String: Any] else { return }
            if let text = data["context"] as? String { contextChanged(String(text.prefix(24000))) }
            if message.name == "articleNotes" {
                if let text = data["selection"] as? String { selectionChanged(String(text.prefix(24000))) }
                if let id = data["note"] as? String, id.count < 300 { noteClicked(id) }
                return
            }
            guard let positionURL,
                  let anchor = data["anchor"] as? String, anchor.count < 300,
                  let offset = data["offset"] as? Double, offset.isFinite, abs(offset) < 1_000_000 else { return }
            if let encoded = try? JSONSerialization.data(withJSONObject: ["anchor": anchor, "offset": offset]) { try? encoded.write(to: positionURL, options: .atomic) }
        }
        weak var container: WebPane.FillContainer?
        var article: FormattedArticle?
        var ready = false
        var rendered: String?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render() }
        func render() {
            guard ready, let article, let container else { return }
            if rendered == article.html { syncMarks(); return }
            articleReady = false
            rendered = article.html
            let position = positionURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            Task { @MainActor [weak self, weak container] in
                guard let container else { return }
                do {
                    _ = try await container.web.callAsyncJavaScript("return await window.renderArticle(html, base, position)", arguments: ["html": article.html, "base": article.source.absoluteString, "position": position], in: nil, contentWorld: .page)
                    self?.container?.web.isHidden = false; self?.container?.fallback.isHidden = true
                    self?.articleReady = true; self?.lastMarks = ""; self?.syncMarks()
                } catch { self?.container?.showSource("Could not render this paper. Choose Source to read the original PDF.") }
            }
        }
        func syncMarks() {
            guard articleReady, let web = container?.web else { return }
            let encoded = (try? JSONSerialization.data(withJSONObject: marks)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            if encoded != lastMarks {
                lastMarks = encoded
                let snapshot = marks
                Task { _ = try? await web.callAsyncJavaScript("return window.setArticleMarks(marks)", arguments: ["marks": snapshot], in: nil, contentWorld: .page) }
            }
            if let requestedReveal, revealRequest != lastRevealRequest {
                lastRevealRequest = revealRequest
                Task {
                    let found = try? await web.callAsyncJavaScript("return window.revealArticleMark(id)", arguments: ["id": requestedReveal], in: nil, contentWorld: .page)
                    if found as? Bool != true { self.revealUnavailable() }
                }
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { container?.showSource("Could not open the formatted reader. Choose Source for the original PDF.") }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { container?.showSource("The formatted reader stopped. Reopen the material or choose Source.") }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                if url.isFileURL, url.fragment != nil { decisionHandler(.allow); return }
                if ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
    }
}

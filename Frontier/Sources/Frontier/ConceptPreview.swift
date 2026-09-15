import SwiftUI
import WebKit

/// FRONTIER_WEBLOG=1 — narrates the preview's load-and-render pipeline to
/// stderr, because a blank pane has half a dozen distinct causes (load never
/// finished, load failed, JS threw, DOM filled but view invisible) that all
/// look identical from the outside.
func weblog(_ message: @autoclosure () -> String) {
    if ProcessInfo.processInfo.environment["FRONTIER_WEBLOG"] == "1" {
        NSLog("WEB %@", message())
    }
}

/// One native container gives WebKit a bounded, opaque reading viewport.
typealias ConceptPreview = WebPane

struct WebPane: NSViewRepresentable {
    let markdown: String
    var contentHeightChanged: ((CGFloat) -> Void)? = nil
    enum Presentation { case reading, card }
    var presentation: Presentation = .reading

    final class FillContainer: NSView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let fallback = NSScrollView()
        let source = NSTextView()
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            web.isHidden = true
            web.underPageBackgroundColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(srgbRed: 35/255, green: 37/255, blue: 33/255, alpha: 1)
                    : NSColor(srgbRed: 247/255, green: 245/255, blue: 239/255, alpha: 1)
            }
            source.backgroundColor = web.underPageBackgroundColor
            source.textColor = .labelColor
            source.string = "Preparing the reading view…"
            source.isEditable = false
            source.font = .systemFont(ofSize: 13)
            source.textContainerInset = NSSize(width: 20, height: 18)
            source.autoresizingMask = [.width]
            source.isHorizontallyResizable = false
            source.isVerticallyResizable = true
            source.textContainer?.widthTracksTextView = true
            fallback.documentView = source
            fallback.hasVerticalScroller = true
            fallback.isHidden = false
            for child in [web, fallback] {
                addSubview(child)
                child.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    child.leadingAnchor.constraint(equalTo: leadingAnchor), child.trailingAnchor.constraint(equalTo: trailingAnchor),
                    child.topAnchor.constraint(equalTo: topAnchor), child.bottomAnchor.constraint(equalTo: bottomAnchor)
                ])
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func showSource(_ markdown: String) {
            source.string = "Formatted view unavailable. Showing readable source text.\n\n" + markdown
            fallback.isHidden = false
            web.isHidden = true
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FillContainer, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 320)
    }

    func makeNSView(context: Context) -> FillContainer {
        let container = FillContainer(frame: .zero)
        let view = container.web
        if contentHeightChanged != nil {
            view.configuration.userContentController.add(context.coordinator, name: "introHeight")
        }
        context.coordinator.contentHeightChanged = contentHeightChanged
        context.coordinator.presentation = presentation
        view.navigationDelegate = context.coordinator
        view.allowsMagnification = true
        context.coordinator.container = container
        context.coordinator.webView = view

        guard let html = Bundle.main.url(forResource: "render", withExtension: "html",
                                         subdirectory: "web")
            ?? Bundle.main.url(forResource: "render", withExtension: "html") else {
            view.loadHTMLString("<p>render.html missing from the bundle</p>", baseURL: nil)
            return container
        }
        // Read access to the enclosing directory, so katex.min.js and the fonts resolve.
        context.coordinator.page = html
        view.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak coordinator = context.coordinator] in
            guard let coordinator, !coordinator.rendered else { return }
            coordinator.container?.showSource(coordinator.pending)
        }
        return container
    }

    func updateNSView(_ container: FillContainer, context: Context) {
        guard let view = context.coordinator.webView else { return }
        weblog("update: container=\(container.frame) web=\(view.frame) markdown=\(markdown.count) chars")
        context.coordinator.contentHeightChanged = contentHeightChanged
        context.coordinator.pending = markdown
        context.coordinator.flush(into: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: FillContainer, coordinator: Coordinator) {
        nsView.web.configuration.userContentController.removeScriptMessageHandler(forName: "introHeight")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var contentHeightChanged: ((CGFloat) -> Void)?
        var presentation: Presentation = .reading
        private var measuredHeight: CGFloat = 0

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "introHeight", message.frameInfo.isMainFrame,
                  let value = message.body as? Double, value.isFinite, value > 0, value < 1_000_000 else { return }
            let height = CGFloat(ceil(value))
            guard abs(height - measuredHeight) > 0.5 else { return }
            measuredHeight = height
            contentHeightChanged?(height)
        }

        var pending: String = ""
        var rendered = false
        var lastRendered: String?
        weak var container: FillContainer?
        var page: URL?
        weak var webView: WKWebView?
        private var ready = false
        private var flushing = false
        private weak var view: WKWebView?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            weblog("didFinish — flushing \(pending.count) pending chars")
            ready = true
            if presentation == .card {
                webView.evaluateJavaScript("""
                    const style = document.createElement('style');
                    style.textContent = 'body {font-size:12px;line-height:1.55;padding:12px;background:#efede7;} h1 {font-size:18px;line-height:1.25;margin-bottom:10px;letter-spacing:-.2px;} @media(prefers-color-scheme:dark){body{background:#2b2d29;}}';
                    document.head.appendChild(style);
                    """, completionHandler: nil)
            }
            if contentHeightChanged != nil {
                webView.evaluateJavaScript("""
                    document.documentElement.style.overflow = '\(presentation == .card ? "auto" : "hidden")';
                    document.body.style.paddingBottom = '\(presentation == .card ? "12px" : "24px")';
                    document.getElementById('out').style.display = 'flow-root';
                    const reportHeight = () => {
                        const out = document.getElementById('out');
                        const padding = parseFloat(getComputedStyle(document.body).paddingBottom);
                        window.webkit.messageHandlers.introHeight.postMessage(out.getBoundingClientRect().bottom + scrollY + padding);
                    };
                    new ResizeObserver(reportHeight).observe(document.getElementById('out'));
                    document.fonts.ready.then(reportHeight);
                    """, completionHandler: nil)
            }
            lastRendered = nil
            view = webView
            flush(into: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) {
            weblog("didFail: \(error.localizedDescription)")
            container?.showSource(pending)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            weblog("didFailProvisional: \(error.localizedDescription)")
            container?.showSource(pending)
        }

        /// WebKit's content process can die out from under the view — under
        /// memory pressure, or a GPU hiccup — and what that looks like on
        /// screen is the reading pane going permanently, silently blank.
        /// Reload the page; didFinish then replays the pending document.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false
            rendered = false
            lastRendered = nil
            container?.showSource(pending)
            guard let page else { return }
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }

        /// Held until the page has loaded, otherwise the first keystrokes are lost.
        func flush(into webView: WKWebView) {
            guard ready else { self.view = webView; return }
            guard !flushing, pending != lastRendered else { return }
            flushing = true
            let document = pending
            // "└ NVIDIA whitepaper" lines are citations, not prose. Marked up
            // here rather than in the stylesheet, because only this side knows
            // that a line beginning with └ means "where the claim above came
            // from" — and a citation set in body text reads as an afterthought.
            let marked = pending.components(separatedBy: "\n").map { line -> String in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("└") else { return line }
                return "<div class=\"cite\">" + t + "</div>"
            }.joined(separator: "\n")
            let data = (try? JSONSerialization.data(withJSONObject: [marked])) ?? Data()
            let json = String(data: data, encoding: .utf8) ?? "[\"\"]"
            // Passing through JSON avoids every quoting and newline hazard. The
            // trailing expression hands back the rendered length, so a failure
            // has an error and a success has a number — a blank pane stops
            // being indistinguishable from a successful render of nothing.
            webView.evaluateJavaScript(
                "window.renderMarkdown(\(json)[0]); window.scrollTo(0,0); document.getElementById('out').innerHTML.length"
            ) { [weak self] value, error in
                guard let self else { return }
                self.flushing = false
                if error != nil || (value as? Int ?? 0) == 0 {
                    self.container?.showSource(self.pending)
                } else {
                    self.rendered = true
                    self.lastRendered = document
                    self.container?.fallback.isHidden = true
                    self.container?.web.isHidden = false
                }
                if self.pending != document { self.flush(into: webView) }
                weblog("render: out=\((value as? Int).map(String.init) ?? "nil") chars"
                       + (error.map { " error=\($0.localizedDescription)" } ?? ""))
            }
        }
    }
}

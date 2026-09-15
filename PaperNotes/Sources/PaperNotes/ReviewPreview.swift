import AppKit
import SwiftUI
import WebKit

@MainActor enum ReviewPreview {
    static func live() {
        guard ProcessInfo.processInfo.environment["LOCAL_APPS_TESTING"] == "1", let path = ProcessInfo.processInfo.environment["PN_REVIEW_CAPTURE"] else { return }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(700))
                let model = AppModel.shared; model.bootstrap()
                if let paper = model.papers.first { model.select(paper.id) }
                try await Task.sleep(for: .seconds(2))
                guard let view = AppDelegate.mainWindow()?.contentView else { throw CocoaError(.coderInvalidValue) }
                func webViews(_ view: NSView) -> [WKWebView] { (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews) }
                guard let web = webViews(view).first else { throw CocoaError(.coderInvalidValue) }
                print("LIVE review DOM: \(String(describing: try await web.evaluateJavaScript("document.body.innerText.length")))")
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.coderInvalidValue) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("PASS actual application window captured")
                exit(0)
            } catch { print("FAIL live review: \(error)"); exit(1) }
        }
    }
    static func run(to path: String) -> Never {
        guard ProcessInfo.processInfo.environment["LOCAL_APPS_TESTING"] == "1" else { print("Use an isolated test data root."); exit(1) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory); app.appearance = NSAppearance(named: .darkAqua)
        Task { @MainActor in
            do {
                let model = AppModel.shared; model.bootstrap()
                var paper = Paper(arxivID: "2510.21600")
                paper.title = "Real-time decoding of the gross code memory with FPGAs"
                paper.authors = ["Maurer et al."]; paper.year = 2025
                paper.body = "## Claim, in my words\n\nThe experiment evaluates real-time decoding.\n\n## Evidence — what convinced me, or didn't\n\nThe reported latency needs to hold under sustained load: $t \\le \\tau$.\n\n## What I didn't understand\n\nHow would this behave under correlated noise?\n\n[Return to source](frontier://source/example?page=2)"
                _ = Library.shared.save(paper); model.refresh(); model.select(paper.id)
                if ProcessInfo.processInfo.environment["PN_PREVIEW_DISCUSSION"] == "1" { model.showingDiscussion = true }
                let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                let view = NSHostingView(rootView: ContentView(model: model).environment(\.colorScheme, .dark))
                window.contentView = view; window.title = "Paper Notes · review check"; window.makeKeyAndOrderFront(nil)
                func webViews(_ view: NSView) -> [WKWebView] { (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews) }
                var web: WKWebView?
                for _ in 0..<80 {
                    web = webViews(view).first
                    if let web, (try? await web.evaluateJavaScript("document.querySelectorAll('.katex').length")) as? Int ?? 0 >= 1 { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                print("web count: \(webViews(view).count), draft: \(model.draft?.id ?? "none")")
                if let web { print("DOM: \(String(describing: try? await web.evaluateJavaScript("document.body.innerText"))) frame \(web.frame)") }
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: rep); try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)) }
                guard let web, (try await web.evaluateJavaScript("document.querySelectorAll('.katex').length")) as? Int ?? 0 >= 1 else { throw CocoaError(.coderInvalidValue) }
                for mode in ["Preview", "Write", "Split"] {
                    UserDefaults.standard.set(mode, forKey: "reviewMode")
                    try await Task.sleep(for: .milliseconds(300))
                    guard view.bounds.height <= 761, web.bounds.width <= 900 else { throw CocoaError(.coderInvalidValue) }
                    print("PASS review mode \(mode): bounded window, live mathematical preview")
                }
                UserDefaults.standard.set("Preview", forKey: "reviewMode")
                try await Task.sleep(for: .milliseconds(200))
                let configuration = WKSnapshotConfiguration()
                let image = try await web.takeSnapshot(configuration: configuration)
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(fileURLWithPath: path + ".web.png"))
                }
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                print("PASS dark review preview, rendered math and source link; saved \(path)")
                exit(0)
            } catch { print("FAIL review preview: \(error)"); exit(1) }
        }
        app.run(); exit(1)
    }
}

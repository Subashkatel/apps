import AppKit
import PDFKit

/// Value snapshots are the only data crossing to the PDF save queue.
struct PDFMark: Sendable {
    // PDFKit drops /NM on serialization; a custom key survives reopen/export.
    static let idKey = PDFAnnotationKey(rawValue: "/FrontierID")
    static let quoteKey = PDFAnnotationKey(rawValue: "/FrontierQuote")
    var quote: String?
    var bounds: CGRect
    var kind: String
    var text: String?
    var id: String?
    var rgba: [Double]
    var quadrilaterals: [CGPoint]?
    init(_ mark: PDFAnnotation) {
        quote = mark.value(forAnnotationKey: Self.quoteKey) as? String
        bounds = mark.bounds; kind = mark.type ?? "Text"; text = mark.contents
        id = mark.value(forAnnotationKey: Self.idKey) as? String ?? mark.value(forAnnotationKey: .name) as? String
        let color = mark.color.usingColorSpace(.deviceRGB) ?? .yellow
        rgba = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        quadrilaterals = mark.quadrilateralPoints?.map(\.pointValue)
    }
    func annotation() -> PDFAnnotation {
        let mark = PDFAnnotation(bounds: bounds, forType: kind == "Highlight" ? .highlight : .text, withProperties: nil)
        if let quote { mark.setValue(quote, forAnnotationKey: Self.quoteKey) }
        mark.contents = text; mark.color = NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        mark.quadrilateralPoints = quadrilaterals?.map { NSValue(point: $0) }
        if let id { mark.setValue(id, forAnnotationKey: PDFMark.idKey) }
        return mark
    }
    static func write(_ pages: [Int: [PDFMark]], original: URL, annotated: URL) throws {
        let source = FileManager.default.fileExists(atPath: annotated.path) ? annotated : original
        guard let doc = PDFDocument(url: source) else { throw FrontierError("Could not open the PDF for saving.") }
        for (index, marks) in pages {
            guard let page = doc.page(at: index) else { continue }
            for mark in page.annotations where mark.type == "Highlight" || mark.type == "Text" { page.removeAnnotation(mark) }
            for mark in marks { page.addAnnotation(mark.annotation()) }
        }
        guard let bytes = doc.dataRepresentation() else { throw FrontierError("Could not serialize PDF annotations.") }
        try bytes.write(to: annotated, options: .atomic)
    }
}

@MainActor final class MarginPDFView: PDFView {
    var annotationClicked: ((PDFAnnotation) -> Void)?
    private var bubbles: [NSButton] = []
    private var marks: [PDFAnnotation] = []
    private var scrollObserver: NSObjectProtocol?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        if let clip = documentView?.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMargin() }
            }
        }
        refreshMargin()
    }
    deinit { if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) } }
    override func layout() { super.layout(); DispatchQueue.main.async { [weak self] in self?.refreshMargin() } }
    func annotationsChanged() {
        // PDFKit caches per-page layers: mark each visible page view dirty after a deletion.
        func invalidate(_ view: NSView) { view.needsDisplay = true; view.subviews.forEach(invalidate) }
        if let documentView { invalidate(documentView) }
        needsDisplay = true; refreshMargin()
    }
    func refreshMargin() {
        var nextMarks: [PDFAnnotation] = []
        var nextFrames: [CGRect] = []
        var seen = Set<String>(); var occupied: [CGFloat] = []
        for page in visiblePages {
            for mark in page.annotations where mark.type == "Highlight" || mark.type == "Text" {
                let id = mark.stableID
                guard seen.insert(id).inserted else { continue }
                let rect = convert(mark.bounds, from: page)
                guard rect.intersects(bounds) else { continue }
                var y = rect.midY - 12
                while occupied.contains(where: { abs($0 - y) < 26 }) { y -= 26 }
                occupied.append(y)
                nextFrames.append(NSRect(x: bounds.maxX - 40, y: min(max(y, bounds.minY + 4), bounds.maxY - 28), width: 26, height: 26))
                nextMarks.append(mark)
            }
        }
        // Reuse controls while scrolling; adding/removing subviews during every layout causes a constraints loop.
        while bubbles.count > nextMarks.count { bubbles.removeLast().removeFromSuperview() }
        while bubbles.count < nextMarks.count {
            let button = NSButton(image: NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "Open annotation")!, target: self, action: #selector(openMark(_:)))
            button.isBordered = false; button.contentTintColor = .systemYellow
            addSubview(button); bubbles.append(button)
        }
        marks = nextMarks
        for index in bubbles.indices {
            let button = bubbles[index]; button.tag = index
            if button.frame != nextFrames[index] { button.frame = nextFrames[index] }
            button.contentTintColor = marks[index].color.withAlphaComponent(1)
            button.toolTip = marks[index].contents ?? "Open annotation"
        }
    }
    @objc private func openMark(_ sender: NSButton) {
        guard marks.indices.contains(sender.tag) else { return }
        annotationClicked?(marks[sender.tag])
    }
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let page = page(for: location, nearest: false), let mark = page.annotation(at: convert(location, to: page)),
           mark.type == "Highlight" || mark.type == "Text" { annotationClicked?(mark) }
        super.mouseDown(with: event)
    }
}

@MainActor extension PDFAnnotation {
    var groupID: String? { value(forAnnotationKey: PDFMark.idKey) as? String ?? value(forAnnotationKey: .name) as? String }
    var stableID: String { groupID ?? String(describing: ObjectIdentifier(self)) }
}

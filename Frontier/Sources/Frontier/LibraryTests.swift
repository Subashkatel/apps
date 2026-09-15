import Foundation
import AppKit

@MainActor enum LibraryTests {
    static func run(_ check: (String, Bool, String) -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("frontier-library-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func verify(_ name: String, _ value: Bool) { check(name, value, "") }
        do {
            for (name, box, rotated) in [
                ("portrait side panel", CGRect(x:182,y:42,width:44,height:243), true),
                ("wide illustration", CGRect(x:23,y:180,width:194,height:102), false),
                ("large hero", CGRect(x:27,y:53,width:186,height:134), false)
            ] {
                let placement = CoverArtworkPlacement(in: box, rotated: rotated)
                let expected: CGFloat = rotated ? 83.0/190 : 190.0/83
                verify("\(name) preserves illustration proportions and bounds", abs(placement.frame.width / placement.frame.height - expected) < 0.0001 && box.insetBy(dx:-0.001,dy:-0.001).contains(placement.frame))
            }
            let designs = CoverDesignStore(file: root.appendingPathComponent("covers.json"))
            let coverIDs = (0..<250).map { "material-\($0)" }
            verify("cover composition structures do not repeat as the catalogue grows", Set((0..<5000).map { CoverComposition(index: $0) }).count == 5000)
            let initial = try designs.assign(Array(coverIDs.prefix(24)))
            verify("first 24 covers receive different illustration families", Set(initial.values.map { $0 % 24 }).count == 24)
            let grown = try designs.assign(coverIDs.reversed())
            verify("new materials never reuse an allocated cover identifier", Set(grown.values).count == 250)
            verify("adding and sorting preserve existing cover designs", initial.allSatisfy { grown[$0.key] == $0.value })
            let reduced = try designs.assign([coverIDs[0]])
            let restoredDesigns = try designs.assign(coverIDs)
            verify("removal and restore preserve reserved cover designs", reduced == grown && restoredDesigns == grown)
            verify("cover allocations survive reopening", try CoverDesignStore(file: designs.file).assign(coverIDs) == grown)
            let graph = GraphSim()
            graph.load(ids: ["a", "b", "c"], edges: [("a", "b", 1)], masses: ["b": 5], size: CGSize(width: 800, height: 600))
            graph.dragging = "a"; graph.dragTarget = CGPoint(x: 300, y: 220)
            graph.step(centre: CGPoint(x: 400, y: 300))
            verify("graph dragging follows the pointer precisely", graph.position("a") == CGPoint(x: 300, y: 220))
            graph.dragging = nil
            for _ in 0..<900 { graph.step(centre: CGPoint(x: 400, y: 300)) }
            verify("graph cools down and remains finite", graph.isSettled && graph.bodies.values.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
            let ids = (0..<197).map { "layout-\($0)" }
            let links: [(String, String, Double)] = (1..<197).map { (ids[$0], ids[$0 - 1], 1.0) }
            let size = CGSize(width: 780, height: 620)
            let layout = ForceLayout.layout(ids: ids, edges: links, size: size)
            let repeatLayout = ForceLayout.layout(ids: ids, edges: links, size: size)
            verify("initial graph layout is deterministic, finite and inside the viewport",
                   layout.count == 197 && ids.allSatisfy { id in
                       guard let p = layout[id]?.position else { return false }
                       return p == repeatLayout[id]?.position && p.x.isFinite && p.y.isFinite && p.x >= 0 && p.y >= 0 && p.x <= size.width && p.y <= size.height
                   })
            let stable = GraphSim()
            stable.load(ids: ids, edges: links, masses: [:], size: size, seeded: layout, settled: true)
            verify("an arranged graph starts settled instead of animating again", stable.isSettled)
            stable.updateMasses([ids[0]: 10])
            verify("graph metadata updates preserve its arrangement", stable.isSettled && ids.allSatisfy { stable.position($0) == layout[$0]?.position })
            let store = MaterialStore(root: root.appendingPathComponent("library"))
            verify("new library starts empty", try store.load().isEmpty)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            // Exercise real PDF/EPUB cover extraction, including original proportions.
            let pdf = root.appendingPathComponent("cover.pdf")
            var pageRect = CGRect(x: 0, y: 0, width: 400, height: 600)
            let consumer = CGDataConsumer(url: pdf as CFURL)!
            let context = CGContext(consumer: consumer, mediaBox: &pageRect, nil)!
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 0.8, green: 0.15, blue: 0.1, alpha: 1)); context.fill(pageRect)
            context.endPDFPage(); context.closePDF()
            let cover = MaterialStore.cover(pdf)
            let image = cover.flatMap(NSImage.init(data:))
            verify("PDF first page becomes a cover with its original proportions", image.map { abs($0.size.width / $0.size.height - 2.0/3.0) < 0.01 } ?? false)
            let pixels = cover.flatMap(NSBitmapImageRep.init(data:))
            let center = pixels.flatMap { $0.colorAt(x: $0.pixelsWide / 2, y: $0.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) }
            verify("PDF cover contains the source page rather than a blank thumbnail", center.map { $0.redComponent > $0.greenComponent + 0.3 && $0.redComponent > $0.blueComponent + 0.3 && $0.alphaComponent > 0.9 } ?? false)
            let book = root.appendingPathComponent("epub-cover")
            try FileManager.default.createDirectory(at: book.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: book.appendingPathComponent("OEBPS"), withIntermediateDirectories: true)
            try "<container><rootfiles><rootfile full-path=\"OEBPS/book.opf\"/></rootfiles></container>".write(to: book.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)
            try "<package><manifest><item id=\"cover\" href=\"cover.png\" media-type=\"image/png\" properties=\"cover-image\"/></manifest></package>".write(to: book.appendingPathComponent("OEBPS/book.opf"), atomically: true, encoding: .utf8)
            try cover?.write(to: book.appendingPathComponent("OEBPS/cover.png"))
            let epub = root.appendingPathComponent("cover.epub")
            _ = try LocalProcess.run(URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-r", epub.path, "META-INF", "OEBPS"], directory: book)
            verify("EPUB uses its embedded cover image", MaterialStore.cover(epub).flatMap(NSImage.init(data:))?.size == image?.size)
            let source = root.appendingPathComponent("source.md")
            try "# One\n\nA formula $x^2$.\n\n# Two\n\nKeep reading.".write(to: source, atomically: true, encoding: .utf8)
            let loaded = try Resource.read(source.path)
            var item = try store.add(loaded)
            try FileManager.default.removeItem(at: source)
            let savedOriginal = try String(contentsOf: store.asset(item, item.originalFile)!)
            verify("original survives source deletion", savedOriginal.contains("A formula"))
            item.notes = "My own thoughts."; item.lastOpened = Date(); item.sectionIndex = 1; item.kind = .book
            try store.save(item)
            item.coverStyle = .designed; try store.save(item)
            let restored = try store.load()[0]
            verify("chosen cover style survives reopening", restored.coverStyle == .designed && !restored.usesOriginalCover)
            let oldPaper = LibraryMaterial(title: "Paper", kind: .paper, format: "PDF")
            let oldBook = LibraryMaterial(title: "Book", kind: .book, format: "PDF")
            verify("papers default to designed covers while books keep originals", !oldPaper.usesOriginalCover && oldBook.usesOriginalCover)
            verify("notes, category and reading position survive restart", restored.notes == item.notes && restored.sectionIndex == 1 && restored.kind == .book && restored.lastOpened != nil)
            verify("extracted sections and math survive restart", restored.sections == loaded.sections && restored.sections[0].text.contains("$x^2$"))
            var concept = Concept(id: "one", title: "One"); concept.courses = ["A course"]
            let collections = MaterialStore.collections([], concepts: [concept])
            verify("existing lessons appear without migrating files", collections.count == 1 && collections[0].conceptIDs == ["one"] && collections[0].isCollection)
            var collection = collections[0]; collection.title = "Renamed course"; collection.notes = "Keep these"; try store.save(collection)
            var next = Concept(id: "two", title: "Two"); next.courses = ["A course"]
            let refreshed = MaterialStore.collections([collection], concepts: [concept, next])
            verify("renamed collections retain identity and new lessons", refreshed.count == 1 && refreshed[0].title == "Renamed course" && Set(refreshed[0].conceptIDs) == ["one", "two"])
            verify("ungrouped lessons remain accessible", MaterialStore.collections([], concepts: [Concept(id: "solo", title: "Solo")]).first?.conceptIDs == ["solo"])
            var imported = item; imported.courseName = "A course"; imported.conceptIDs = ["one"]
            verify("imported resource does not produce duplicate course card", MaterialStore.collections([imported], concepts: [concept]).count == 1)
            try Data("broken record".utf8).write(to: store.directory(item.id).appendingPathComponent("material.json"))
            do { _ = try store.load(); verify("corrupt library is reported, not treated as empty", false) }
            catch { verify("corrupt library is reported, not treated as empty", true) }
            verify("cover choice is stable", item.palette == restored.palette && (0..<8).contains(item.palette))
        } catch { check("library storage checks", false, error.localizedDescription) }
    }
}

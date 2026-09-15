import AppKit
import Foundation
import PDFKit
import CryptoKit

struct LibraryMaterial: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case book = "Books", paper = "Papers", note = "Notes", course = "Courses" }
    var id: String = UUID().uuidString
    var title: String
    var kind: Kind
    var format: String
    var origin: String = ""
    var added: Date = Date()
    var lastOpened: Date?
    var sectionIndex: Int = 0
    var notes: String = ""
    var conceptIDs: [String] = []
    var courseName: String?
    var originalFile: String?
    var coverFile: String?
    enum CoverStyle: String, Codable, CaseIterable { case designed = "Designed", original = "Original page" }
    var coverStyle: CoverStyle?
    var usesOriginalCover: Bool { coverStyle == .original || (coverStyle == nil && kind != .paper) }
    var annotatedFile: String?
    var sections: [Resource.Section] = []

    var loaded: Resource.Loaded { .init(name: courseName ?? title, origin: origin, sections: sections) }
    var isCollection: Bool { format == "Collection" }
    var palette: Int { Int(Array(SHA256.hash(data: Data(id.utf8)))[0]) % 8 }
    static func courseID(_ name: String) -> String {
        "course-" + SHA256.hash(data: Data(name.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// One atomic record per material; originals and covers live alongside it.
/// Existing lessons are projected into collections without rewriting their files.
struct MaterialStore {
    var root: URL
    @MainActor static var live: MaterialStore { MaterialStore(root: Store.root.appendingPathComponent("library")) }
    func directory(_ id: String) -> URL { root.appendingPathComponent(id) }
    func asset(_ item: LibraryMaterial, _ name: String?) -> URL? {
        guard let name, name == URL(fileURLWithPath: name).lastPathComponent, name != ".", name != "..",
              item.id == URL(fileURLWithPath: item.id).lastPathComponent, item.id != ".", item.id != ".." else { return nil }
        return directory(item.id).appendingPathComponent(name)
    }
    func load() throws -> [LibraryMaterial] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }.compactMap { folder in
                let record = folder.appendingPathComponent("material.json")
                guard FileManager.default.fileExists(atPath: record.path) else { return nil }
                let item = try JSONDecoder().decode(LibraryMaterial.self, from: Data(contentsOf: record))
                guard item.id == folder.lastPathComponent else { throw FrontierError("A library record has an invalid identifier.") }
                return item
            }
    }
    func save(_ item: LibraryMaterial) throws {
        guard !item.id.isEmpty, item.id == URL(fileURLWithPath: item.id).lastPathComponent, item.id != ".", item.id != ".." else {
            throw FrontierError("Invalid material identifier.")
        }
        let folder = directory(item.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(item).write(to: folder.appendingPathComponent("material.json"), options: .atomic)
    }
    func add(_ loaded: Resource.Loaded) throws -> LibraryMaterial {
        let source = URL(fileURLWithPath: (loaded.origin as NSString).expandingTildeInPath)
        let remote = loaded.origin.hasPrefix("https://") || loaded.origin.hasPrefix("http://")
        let ext = loaded.original.map { URL(fileURLWithPath: $0.filename).pathExtension.lowercased() }
            ?? (remote ? "" : source.pathExtension.lowercased())
        var item = LibraryMaterial(title: loaded.name, kind: ext == "epub" ? .book : (ext == "pdf" ? .paper : .note),
                                   format: ext.isEmpty ? "Web" : ext.uppercased(), origin: loaded.origin, sections: loaded.sections)
        let folder = directory(item.id)
        do {
            if let original = loaded.original { item = try attach(original, to: item) }
            else if !remote, FileManager.default.fileExists(atPath: source.path) {
                item = try attach(.init(filename: source.lastPathComponent, data: Data(contentsOf: source)), to: item)
            } else { try save(item) }
            return item
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
    /// Publish the record only after its source and cover are safely on disk.
    /// Unique names keep a failed replacement from damaging the previous source.
    func attach(_ original: Resource.Original, to existing: LibraryMaterial) throws -> LibraryMaterial {
        var item = existing
        guard !item.id.isEmpty, item.id == URL(fileURLWithPath: item.id).lastPathComponent, item.id != ".", item.id != ".." else { throw FrontierError("Invalid material identifier.") }
        let ext = URL(fileURLWithPath: original.filename).pathExtension.lowercased()
        guard ResourceFiles.extensions.contains(ext), !original.data.isEmpty else { throw FrontierError("Unsupported or empty original document.") }
        let folder = directory(item.id), token = UUID().uuidString
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "original-" + token + "." + ext
        let file = folder.appendingPathComponent(name)
        let coverName = "cover-" + token + ".png"
        do {
            try original.data.write(to: file, options: .atomic)
            item.originalFile = name
            item.annotatedFile = nil
            item.coverFile = nil
            if let cover = Self.cover(file) {
                try cover.write(to: folder.appendingPathComponent(coverName), options: .atomic)
                item.coverFile = coverName
            }
            if !item.isCollection { item.format = ext.uppercased() }
            try save(item)
            return item
        } catch {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(coverName))
            throw error
        }
    }
    func existingOriginal(_ item: LibraryMaterial) -> URL? {
        guard let file = asset(item, item.originalFile), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }
    @MainActor static func collections(_ saved: [LibraryMaterial], concepts: [Concept]) -> [LibraryMaterial] {
        var items = saved
        let names = Set(concepts.flatMap(\.courses)).sorted()
        for name in names where !saved.contains(where: { $0.courseName == name }) {
            let lessons = concepts.filter { $0.courses.contains(name) }.sorted { $0.addedOn < $1.addedOn }
            items.append(LibraryMaterial(id: LibraryMaterial.courseID(name), title: name, kind: .course,
                format: "Collection", added: lessons.first?.addedOn ?? Date(), conceptIDs: lessons.map(\.id), courseName: name))
        }
        let loose = concepts.filter { $0.courses.isEmpty }
        if !loose.isEmpty, !items.contains(where: { $0.id == "uncategorized-lessons" }) {
            items.append(LibraryMaterial(id: "uncategorized-lessons", title: "Independent concepts", kind: .course,
                format: "Collection", added: loose.map(\.addedOn).min() ?? Date(), conceptIDs: loose.map(\.id)))
        }
        // A saved collection's membership remains live as the graph grows.
        for index in items.indices where items[index].isCollection {
            items[index].conceptIDs = concepts.filter {
                items[index].id == "uncategorized-lessons" ? $0.courses.isEmpty : $0.courses.contains(items[index].courseName ?? "")
            }.sorted { $0.addedOn == $1.addedOn ? $0.id < $1.id : $0.addedOn < $1.addedOn }.map(\.id)
        }
        let removed = Set(((try? RemovedMaterial.load()) ?? []).map(\.id))
        return items.filter { !removed.contains($0.id) }
    }
    static func cover(_ url: URL) -> Data? {
        var image: NSImage?
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
            // PDF thumbnails may draw lazily during encoding. Retain the document
            // until rasterization finishes; retaining only its page is insufficient.
            return withExtendedLifetime(document) {
                let thumbnail = page.thumbnail(of: NSSize(width: 440, height: 620), for: .mediaBox)
                guard let tiff = thumbnail.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
                return bitmap.representation(using: .png, properties: [:])
            }
        } else if url.pathExtension.lowercased() == "epub", let archive = try? BookArchive(url),
                  let container = try? TextXML(data: archive.read("META-INF/container.xml"), mode: .container),
                  let path = container.packagePath, let package = try? TextXML(data: archive.read(path), mode: .package),
                  let coverID = package.coverID, let entry = package.manifest[coverID],
                  let resolved = try? archive.resolve(entry.href, relativeTo: path), let data = try? archive.read(resolved) {
            image = NSImage(data: data)
        }
        guard let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

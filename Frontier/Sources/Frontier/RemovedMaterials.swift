import Foundation

/// Reversible removal: source documents, annotations, and lesson files stay intact.
struct RemovedMaterial: Codable {
    var id: String
    var title: String
    var lessonIDs: [String]
    @MainActor static var file: URL { Store.root.appendingPathComponent("removed-materials.json") }
    @MainActor static func load() throws -> [Self] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: file))
    }
    @MainActor static func save(_ items: [Self]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: file, options: .atomic)
    }
}

extension Model {
    func removeMaterial(_ item: LibraryMaterial) throws {
        guard busy == nil else { throw FrontierError("Wait for the current import to finish before removing material.") }
        for reader in pdfReaders.values where reader.dirty { reader.save() }
        guard !hasUnsavedAnnotations else { throw FrontierError("Save your PDF annotations before removing this material.") }
        let usedElsewhere = Set(materials.filter { $0.id != item.id }.flatMap { lessons(for: $0).map(\.id) })
        let exclusive = lessons(for: item).map(\.id).filter { !usedElsewhere.contains($0) }
        var removed = try RemovedMaterial.load()
        removed.removeAll { $0.id == item.id }
        removed.append(.init(id: item.id, title: item.title, lessonIDs: exclusive))
        try RemovedMaterial.save(removed)
        selected = nil; readingMaterialID = nil; sourceMaterial = nil; graphFocus = nil
        load(); screen = .library
    }
    func restoreMaterial(_ id: String) {
        do { try RemovedMaterial.save(RemovedMaterial.load().filter { $0.id != id }); load() }
        catch { note = error.localizedDescription }
    }
}

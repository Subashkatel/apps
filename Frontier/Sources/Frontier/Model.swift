import SwiftUI
import LocalSupport

/// What the window is looking at, and the few things it can do.
@MainActor
final class Model: ObservableObject {
    @Published var concepts: [Concept] = []
    enum Screen: String, CaseIterable { case library = "Library", read = "Read", graph = "Graph" }
    @Published var screen: Screen = .library
    @Published var materials: [LibraryMaterial] = [] { didSet { assignCoverDesigns() } }
    @Published private(set) var coverDesigns: [String: Int] = [:]
    private func assignCoverDesigns() {
        let ids = materials.sorted { $0.id < $1.id }.map(\.id)
        guard ids.contains(where: { coverDesigns[$0] == nil }) else { return }
        do { coverDesigns = try CoverDesignStore(file: Store.root.appendingPathComponent("cover-designs.json")).assign(ids) }
        catch { note = "Could not assign cover designs: " + error.localizedDescription }
    }
    @Published var graphFocus: String?
    @Published var readingMode: ReadingMode = .learn
    @Published var showingDiscussion = false
    var discussions: [String: AIConversation] = [:]
    var articleContexts: [String: String] = [:]
    @Published var passageExplanation: String?
    var pdfReaders: [String: SourcePDF] = [:]
    @Published var sourceMaterial: LibraryMaterial?
    @Published var readingMaterialID: String?
    @Published var selected: String?
    @Published var busy: String?
    /// Set when a background job says something worth reading — a count, or a
    /// reason it could not run.
    @Published var note: String?

    /// Stored, not computed. These walk the whole dependency graph (~9 ms at
    /// 275 concepts, measured with --bench), and as computed properties the
    /// sidebar recomputed them for every row of every body evaluation — a
    /// hundred milliseconds per click. Statuses only change through this
    /// class, so recomputing on load() is both cheaper and still correct.
    @Published private(set) var session: [Concept] = []
    @Published private(set) var ready: [Concept] = []

    init(concepts: [Concept] = []) {
        self.concepts = concepts
        session = Frontier.session(concepts)
        ready = Frontier.ready(concepts)
    }

    func load() {
        Store.shared.bootstrap()
        concepts = Store.shared.concepts
        session = Frontier.session(concepts)
        ready = Frontier.ready(concepts)
        if selected == nil { selected = session.first?.id }
        do { materials = MaterialStore.collections(try MaterialStore.live.load(), concepts: concepts) }
        catch { note = "Could not load the library: " + error.localizedDescription }

    }

    var current: Concept? { selected.flatMap { id in concepts.first { $0.id == id } } }

    var readingMaterial: LibraryMaterial? { materials.first { $0.id == readingMaterialID } }
    func lessons(for item: LibraryMaterial) -> [Concept] {
        let ids = Set(item.conceptIDs)
        return concepts.filter { ids.contains($0.id) || (item.courseName != nil && $0.courses.contains(item.courseName!)) }
            .sorted { $0.addedOn == $1.addedOn ? $0.id < $1.id : $0.addedOn < $1.addedOn }
    }
    func saveMaterial(_ item: LibraryMaterial) throws {
        try MaterialStore.live.save(item)
        if materials.first(where: { $0.id == item.id })?.originalFile != item.originalFile { articleContexts[item.id] = nil }
        if let i = materials.firstIndex(where: { $0.id == item.id }) { materials[i] = item }
        else { materials.append(item) }
    }
    func openMaterial(_ item: LibraryMaterial) {
        readingMode = .learn; sourceMaterial = nil; passageExplanation = nil
        var updated = item; updated.lastOpened = Date()
        do { try saveMaterial(updated) } catch { note = error.localizedDescription }
        if item.sections.isEmpty {
            readingMode = .walkthrough; readingMaterialID = item.id
            selected = lessons(for: item).first(where: { !$0.isKnown })?.id ?? lessons(for: item).first?.id
        } else { readingMaterialID = item.id }
        screen = .read
    }
    /// An explicit graph click chooses what Read opens; hovering never does.
    func selectGraphConcept(_ id: String) {
        graphFocus = id; selected = id
        readingMaterialID = nil; sourceMaterial = nil; passageExplanation = nil; readingMode = .walkthrough
    }
    func openLesson(_ concept: Concept) {
        readingMode = .walkthrough; sourceMaterial = nil; passageExplanation = nil
        readingMaterialID = nil; selected = concept.id; screen = .read
    }
    func moveSection(_ index: Int) {
        guard var item = readingMaterial, item.sections.indices.contains(index) else { return }
        item.sectionIndex = index; item.lastOpened = Date()
        do { try saveMaterial(item) } catch { note = error.localizedDescription }
    }
    func addMaterial(_ loaded: Resource.Loaded) async throws -> LibraryMaterial {
        if let existing = materials.first(where: { !$0.isCollection && Resource.canonicalOrigin($0.origin) == Resource.canonicalOrigin(loaded.origin) }) {
            if MaterialStore.live.existingOriginal(existing) == nil, let original = loaded.original {
                let store = MaterialStore.live
                var repaired = existing
                repaired.sections = loaded.sections; repaired.format = URL(fileURLWithPath: original.filename).pathExtension.uppercased()
                if repaired.format == "PDF" { repaired.kind = .paper }
                let updated = try await Task.detached { try store.attach(original, to: repaired) }.value
                try saveMaterial(updated)
                return updated
            }
            return existing
        }
        let store = MaterialStore.live
        let item = try await Task.detached { try store.add(loaded) }.value
        materials.append(item)
        return item
    }

    func source(for concept: Concept) -> LibraryMaterial? {
        materials.first { $0.conceptIDs.contains(concept.id) || ($0.courseName.map { concept.courses.contains($0) } ?? false) }
    }
    func openOriginal(_ item: LibraryMaterial) {
        guard let url = MaterialStore.live.existingOriginal(item) else {
            note = "This material has no attached original yet. Open its library details and choose Attach original."
            return
        }
        if url.pathExtension.lowercased() == "pdf" { sourceMaterial = item; readingMaterialID = item.id; screen = .read; readingMode = .source }
        else if !NSWorkspace.shared.open(url) { note = "macOS could not open this document. Install an app that supports its format." }
    }

    func mark(_ concept: Concept, _ status: Concept.Status) {
        var c = concept
        c.status = status
        c.learnedOn = status == .known ? Date() : nil
        Store.shared.save(c)
        load()
        // Learning something changes what is ready, so the next pick is
        // recomputed rather than left stale.
        if status == .known, selected == concept.id { selected = session.first?.id }
    }

    /// Writes the entry for a concept. Off the main thread — the CLI takes
    /// minutes, and a frozen window is not a progress indicator.
    func write(_ concept: Concept) {
        guard busy == nil else { return }
        guard Tutor.isAvailable else {
            note = Tutor.configurationError ?? "Choose an AI provider in AI settings."
            return
        }
        busy = concept.id
        let context = concepts
        Task.detached {
            let written = Tutor.write(concept, context: context)
            await MainActor.run {
                self.busy = nil
                guard let written else { self.note = Tutor.lastError ?? "No answer from the model."; return }
                var c = concept
                c.body = written.body
                c.sources = written.sources
                Store.shared.save(c)
                self.load()
            }
            // Link checking is slower than writing and matters less, so the
            // entry appears first and the ticks arrive after.
            let checked = written?.sources.map { s -> Concept.Source in
                var s = s; s.reachable = SourceCheck.reachable(s.url); return s
            } ?? []
            await MainActor.run {
                guard var c = Store.shared.concept(concept.id), !checked.isEmpty else { return }
                c.sources = checked
                Store.shared.save(c)
                self.load()
            }
        }
    }

    /// Generates the walked-through version.
    func explain(_ concept: Concept) {
        guard busy == nil else { return }
        guard Tutor.isAvailable else { note = Tutor.configurationError ?? "Choose an AI provider in AI settings."; return }
        busy = concept.id
        let context = concepts
        Task.detached {
            let text = Tutor.walkthrough(concept, context: context)
            await MainActor.run {
                self.busy = nil
                guard let text, !text.isEmpty else {
                    self.note = "No answer — \(Tutor.lastError ?? "no detail")"
                    return
                }
                var c = concept
                c.walkthrough = text
                Store.shared.save(c)
                self.load()
            }
        }
    }

    /// One resource, covered end to end. What "Import" in the toolbar runs.
    @Published var importProgress: String?

    func importResource(_ loaded: Resource.Loaded, materialID: String? = nil) {
        guard busy == nil else { return }
        guard Tutor.isAvailable else { note = Tutor.configurationError ?? "Choose an AI provider in AI settings."; return }
        busy = "import"
        importProgress = "Reading it…"
        let existing = concepts
        Task.detached {
            let batches = Resource.batches(loaded.sections)
            var proposed: [Concept] = []
            var addedTotal = 0
            for (i, batch) in batches.enumerated() {
                await MainActor.run {
                    self.importProgress = "\(loaded.name) — section \(i + 1) of \(batches.count)…"
                }
                let concepts = Tutor.digest(
                    resource: loaded.name,
                    sections: batch.map { ($0.title, $0.text) },
                    existing: existing, proposed: proposed)
                if concepts.isEmpty, let error = Tutor.lastError {
                    let completed = addedTotal
                    await MainActor.run {
                        self.busy = nil; self.importProgress = nil
                        self.note = "Generation stopped after \(completed) lessons. Your material and completed lessons are saved. " + error
                        self.load()
                    }
                    return
                }
                proposed += concepts
                // Saved as they arrive, so a failure halfway keeps the chapters
                // already digested rather than discarding twenty minutes.
                addedTotal += await MainActor.run { Store.shared.add(concepts) }
                await MainActor.run {
                    if let materialID, var item = self.materials.first(where: { $0.id == materialID }) {
                        item.conceptIDs = Array(Set(item.conceptIDs + concepts.map(\.id))).sorted()
                        item.courseName = loaded.name
                        do { try self.saveMaterial(item) } catch { self.note = error.localizedDescription }
                    }
                    self.load()
                }
            }
            let total = addedTotal, name = loaded.name
            await MainActor.run {
                self.busy = nil; self.importProgress = nil
                self.note = total == 0
                    ? "Nothing came back — \(Tutor.lastError ?? "no detail")."
                    : "Imported \(total) concepts from \(name). The daily session now walks through it in order."
                self.load()
            }
        }
    }

    /// Extends the graph, filling its own holes first.
    func grow(_ count: Int = 12) {
        guard busy == nil else { return }
        guard Tutor.isAvailable else {
            note = Tutor.configurationError ?? "Choose an AI provider in AI settings."
            return
        }
        busy = "grow"
        let existing = concepts
        Task.detached {
            // From the courses, not from thin air: extending the graph should
            // continue the syllabi it was built from.
            let fetched = Courses.all.compactMap { course -> (name: String, topics: [String])? in
                let topics = Courses.topics(of: course)
                return topics.isEmpty ? nil : (course.name, topics)
            }
            let proposed = fetched.isEmpty
                ? Tutor.expand(seeds: Frontier.missing(existing), existing: existing, count: count)
                : Tutor.next(from: fetched, existing: existing, count: count)
            await MainActor.run {
                let added = Store.shared.add(proposed)
                self.busy = nil
                self.note = added == 0 ? "Nothing new came back." : "Added \(added) concepts."
                self.load()
            }
        }
    }
}

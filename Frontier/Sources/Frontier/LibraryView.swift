import AppKit
import SwiftUI

/// The same warm paper, olive accents and Georgia headings as the approved preview.
enum LibraryTheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let n = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
        })
    }
    static let paper = adaptive(0xf7f5ef, 0x232521)
    static let chrome = adaptive(0xefede7, 0x2b2d29)
    static let ink = adaptive(0x252921, 0xeeeee7)
    static let muted = adaptive(0x717469, 0xaeb2a6)
    static let rule = adaptive(0xdedfd5, 0x41463b)
    static let accent = adaptive(0x536246, 0xc4d4af)
    static func color(_ n: UInt32) -> Color { Color(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255) }
}

struct LibraryPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(LibraryTheme.paper)
            .background(LibraryTheme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.45)
    }
}

struct MaterialCover: View {
    let item: LibraryMaterial
    let design: Int
    var small = false
    @State private var image: NSImage?
    private var aspectRatio: CGFloat {
        if item.usesOriginalCover, let image, image.size.width > 0, image.size.height > 0 {
            return image.size.width / image.size.height
        }
        return item.kind == .book || item.kind == .course ? 2.0 / 3.0 : 1.0 / sqrt(2.0)
    }
    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height * aspectRatio)
            let height = width / aspectRatio
            artwork(width: width, height: height)
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: 2))
                .shadow(color: .black.opacity(0.10), radius: 3, x: 1, y: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .accessibilityHidden(true)
        .task(id: "\(item.coverFile ?? "")-\(item.usesOriginalCover)") {
            guard item.usesOriginalCover, let url = MaterialStore.live.asset(item, item.coverFile) else { image = nil; return }
            image = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }
    @ViewBuilder private func artwork(width: CGFloat, height: CGFloat) -> some View {
        if item.usesOriginalCover, let image {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            DesignedCover(item: item, design: design)
        }
    }
}

struct LibraryView: View {
    @ObservedObject var model: Model
    var add: () -> Void
    @State private var filter: LibraryMaterial.Kind?
    @State private var search = ""
    @State private var sortByTitle = false
    @State private var detail: LibraryMaterial?
    @AppStorage("frontier.library.compact") private var compact = false

    private var filtered: [LibraryMaterial] {
        model.materials.filter { (filter == nil || $0.kind == filter) && (search.isEmpty || $0.title.localizedStandardContains(search)) }
            .sorted { sortByTitle ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.added > $1.added }
    }
    private var recent: [LibraryMaterial] {
        Array(model.materials.filter { $0.lastOpened != nil }.sorted { $0.lastOpened! > $1.lastOpened! }.prefix(2))
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Your library").font(.custom("Georgia", size: 33)).tracking(-0.9)
                            Text("A place for what you’re curious about.").font(.system(size: 12)).foregroundStyle(LibraryTheme.muted)
                        }
                        Spacer()
                        Button(action: add) { Label("Add material", systemImage: "plus") }
                            .buttonStyle(LibraryPrimaryButton())
                    }.padding(.bottom, 28)
                    if !recent.isEmpty {
                        Text("Continue reading").font(.system(size: 13, weight: .medium)).padding(.bottom, 12)
                        HStack(spacing: 30) {
                            ForEach(recent) { item in
                                Button { model.openMaterial(item) } label: { resume(item) }.buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(.bottom, 26)
                        LibraryTheme.rule.frame(height: 1).padding(.bottom, 23)
                    }
                    HStack(spacing: 16) {
                        filterButton("All materials", nil)
                        ForEach(LibraryMaterial.Kind.allCases, id: \.self) { kind in filterButton(kind.rawValue, kind) }
                        Spacer(minLength: 8)
                        Image(systemName: "magnifyingglass").foregroundStyle(LibraryTheme.muted)
                        TextField("Search library", text: $search).textFieldStyle(.plain).frame(width: 125)
                        Menu {
                            Button("Recently added") { sortByTitle = false }
                            Button("Title") { sortByTitle = true }
                            Divider()
                            Toggle("Compact covers", isOn: $compact)
                            let removed = (try? RemovedMaterial.load()) ?? []
                            if !removed.isEmpty {
                                Menu("Restore removed material") {
                                    ForEach(removed, id: \.id) { item in Button(item.title) { model.restoreMaterial(item.id) } }
                                }
                            }
                        } label: { Image(systemName: "line.3.horizontal.decrease") }
                        .menuStyle(.borderlessButton).frame(width: 24).help("Sort and density")
                    }.font(.system(size: 12)).padding(.bottom, 20)
                    if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: search.isEmpty && filter == nil ? "books.vertical" : "magnifyingglass").font(.system(size: 28, weight: .light))
                            Text(model.materials.isEmpty ? "Make room for a new idea." : "No matching materials.").font(.custom("Georgia", size: 23))
                            Text(model.materials.isEmpty ? "Add a book, paper, note or web page to begin." : "Try another search or category.").foregroundStyle(LibraryTheme.muted)
                            if model.materials.isEmpty { Button("Add your first material", action: add) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 90)
                    } else {
                        let count = max(2, Int((geometry.size.width - 72) / (compact ? 154 : 195)))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: count), alignment: .leading, spacing: 28) {
                            ForEach(filtered) { item in
                                Button { detail = item } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        MaterialCover(item: item, design: model.coverDesigns[item.id] ?? 0).frame(height: compact ? 190 : 235)
                                        Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading).padding(.top, 11)
                                        Text(metadata(item)).font(.system(size: 11)).foregroundStyle(LibraryTheme.muted).padding(.top, 4)
                                        Text(status(item)).font(.system(size: 11)).foregroundStyle(LibraryTheme.muted).padding(.top, 8)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).help("Open \(item.title)")
                            }
                        }
                    }
                    Text("\(filtered.count) \(filtered.count == 1 ? "material" : "materials")")
                        .font(.system(size: 11)).foregroundStyle(LibraryTheme.muted).padding(.top, 30)
                }.padding(.horizontal, 36).padding(.top, 31).padding(.bottom, 28)
            }.background(LibraryTheme.paper).foregroundStyle(LibraryTheme.ink)
        }
        .sheet(item: $detail) { item in MaterialDetail(model: model, original: item) }
    }
    private func filterButton(_ title: String, _ kind: LibraryMaterial.Kind?) -> some View {
        Button { filter = kind } label: {
            Text(title).foregroundStyle(filter == kind ? LibraryTheme.ink : LibraryTheme.muted)
                .padding(.vertical, 5).overlay(alignment: .bottom) { if filter == kind { LibraryTheme.ink.frame(height: 1) } }
        }.buttonStyle(.plain)
    }
    private func metadata(_ item: LibraryMaterial) -> String {
        item.isCollection ? "\(model.lessons(for: item).count) concepts · Collection" : "\(item.format) · \(item.sections.count) \(item.sections.count == 1 ? "section" : "sections")"
    }
    private func status(_ item: LibraryMaterial) -> String {
        if item.isCollection {
            let lessons = model.lessons(for: item), known = lessons.filter(\.isKnown).count
            return known == 0 ? "Not started" : "\(known) of \(lessons.count) learned"
        }
        return item.lastOpened == nil ? "Not started" : "Section \(item.sectionIndex + 1) of \(item.sections.count)"
    }
    private func resume(_ item: LibraryMaterial) -> some View {
        HStack(spacing: 17) {
            MaterialCover(item: item, design: model.coverDesigns[item.id] ?? 0, small: true).frame(width: 62, height: 86)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Text(metadata(item)).font(.system(size: 12)).foregroundStyle(LibraryTheme.muted)
                let lessons = model.lessons(for: item)
                let progress = item.isCollection ? Double(lessons.filter(\.isKnown).count) / Double(max(1, lessons.count)) : Double(item.sectionIndex + 1) / Double(max(1, item.sections.count))
                GeometryReader { geo in ZStack(alignment: .leading) {
                    LibraryTheme.rule
                    LibraryTheme.accent.frame(width: geo.size.width * min(1, progress))
                }}.frame(maxWidth: 235).frame(height: 3).padding(.top, 6)
                Text(status(item)).font(.system(size: 11)).foregroundStyle(LibraryTheme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right").foregroundStyle(LibraryTheme.muted)
        }.contentShape(Rectangle())
    }
}

struct MaterialDetail: View {
    @ObservedObject var model: Model
    let original: LibraryMaterial
    @Environment(\.dismiss) private var dismiss
    @State private var editingTitle = false
    @State private var confirmingRemove = false
    @State private var draft: LibraryMaterial?
    @State private var error: String?
    private var item: LibraryMaterial { draft ?? original }
    private func commit() -> Bool {
        do { try model.saveMaterial(item); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 28) {
                MaterialCover(item: item, design: model.coverDesigns[item.id] ?? 0).frame(width: 180, height: 245)
                VStack(alignment: .leading, spacing: 13) {
                    Text(item.format.uppercased()).font(.system(size: 10)).tracking(1.3).foregroundStyle(LibraryTheme.muted)
                    if editingTitle {
                        TextField("Title", text: Binding(get: { item.title }, set: { var d = item; d.title = $0; draft = d }), axis: .vertical)
                            .lineLimit(1...5).textFieldStyle(.roundedBorder).font(.custom("Georgia", size: 25))
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Finish renaming") { editingTitle = false }.font(.caption)
                    } else {
                        Text(item.title).font(.custom("Georgia", size: 27)).fixedSize(horizontal: false, vertical: true)
                        Button("Rename") { editingTitle = true }.font(.caption)
                    }
                    Picker("Category", selection: Binding(get: { item.kind }, set: { var d = item; d.kind = $0; draft = d })) {
                        ForEach(LibraryMaterial.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.frame(maxWidth: 220)
                    if item.coverFile != nil {
                        Picker("Cover", selection: Binding(get: { item.usesOriginalCover ? LibraryMaterial.CoverStyle.original : .designed }, set: { var d = item; d.coverStyle = $0; draft = d })) {
                            ForEach(LibraryMaterial.CoverStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.frame(maxWidth: 220)
                    }
                    Text(item.isCollection ? "A collection from your existing learning graph." : "\(item.sections.count) \(item.sections.count == 1 ? "section" : "sections") · Added \(item.added.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12)).foregroundStyle(LibraryTheme.muted)
                    if !item.origin.isEmpty {
                        Text(item.origin).font(.caption).foregroundStyle(LibraryTheme.muted).lineLimit(2).textSelection(.enabled)
                    }
                    Button(item.lastOpened == nil ? "Start reading" : "Continue reading") {
                        if commit() { model.openMaterial(item); dismiss() }
                    }.buttonStyle(LibraryPrimaryButton())
                    if MaterialStore.live.existingOriginal(item) != nil {
                        Button("Read source") { if commit() { model.openOriginal(item); dismiss() } }
                    }
                    Button("Attach original…") {
                        if commit() { Task { do { if let updated = try await model.attachOriginal(to: item) { draft = updated } } catch { self.error = error.localizedDescription } } }
                    }
                }
                Spacer(minLength: 0)
            }
            Divider()
            HStack {
                Text("Learning path").font(.system(size: 13, weight: .medium))
                Spacer()
                if !item.sections.isEmpty {
                    Button(model.lessons(for: item).isEmpty ? "Generate lessons" : "Continue generating") {
                        if commit() { model.importResource(item.loaded, materialID: item.id); dismiss() }
                    }.disabled(model.busy != nil)
                }
            }
            let lessons = model.lessons(for: item)
            if lessons.isEmpty {
                Text("Generate a learning path with your selected AI whenever you’re ready.").font(.system(size: 12)).foregroundStyle(LibraryTheme.muted)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(lessons) { lesson in
                            Button { if commit() { model.openLesson(lesson); dismiss() } } label: {
                                HStack { Image(systemName: lesson.isKnown ? "checkmark.circle" : "circle"); Text(lesson.plainTitle); Spacer(); Image(systemName: "arrow.right") }
                            }.buttonStyle(.plain)
                        }
                    }.font(.system(size: 12)).padding(.trailing, 14)
                }.frame(maxHeight: 110)
            }
            Text("Your notes").font(.system(size: 13, weight: .medium))
            TextEditor(text: Binding(get: { item.notes }, set: { var d = item; d.notes = $0; draft = d }))
                .font(.system(size: 13)).scrollContentBackground(.hidden).frame(height: 100).padding(8).background(LibraryTheme.chrome).clipShape(.rect(cornerRadius: 6))
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Remove…", role: .destructive) { confirmingRemove = true }.disabled(model.busy != nil)
                Text("Changes save with Done.").font(.caption).foregroundStyle(LibraryTheme.muted)
                Spacer()
                Button("Done") { if commit() { dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 690).background(LibraryTheme.paper).foregroundStyle(LibraryTheme.ink)
            .buttonStyle(LibrarySecondaryButton())
            .interactiveDismissDisabled(draft != nil).tint(LibraryTheme.accent)
            .confirmationDialog("Remove “\(item.title)” from Frontier?", isPresented: $confirmingRemove) {
                Button("Remove material", role: .destructive) {
                    do { try model.removeMaterial(item); dismiss() } catch { self.error = error.localizedDescription }
                }
            } message: { Text("Its exclusive lessons will also leave Read and Graph. Shared lessons remain. Files and annotations are kept; restore this item from the library’s sort menu.") }
    }
}

struct MaterialReader: View {
    @ObservedObject var model: Model
    let material: LibraryMaterial
    private var index: Int { max(0, min(material.sectionIndex, material.sections.count - 1)) }
    var body: some View {
        VStack(spacing: 0) {
            if material.originalFile?.lowercased().hasSuffix(".pdf") == true {
                FormattedMaterialReader(model: model, material: material)
            } else if !material.sections.isEmpty {
                HStack {
                    Picker("Section", selection: Binding(get: { index }, set: { model.moveSection($0) })) {
                        ForEach(Array(material.sections.enumerated()), id: \.offset) { offset, section in
                            Text("\(offset + 1). \(section.title)").tag(offset)
                        }
                    }.labelsHidden()
                    Spacer()
                    Text("\(index + 1) / \(material.sections.count)").font(.caption).foregroundStyle(LibraryTheme.muted)
                }.padding(.horizontal, 22).padding(.vertical, 12)
                ConceptPreview(markdown: "# " + material.sections[index].title + "\n\n" + material.sections[index].text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    Button("Previous section") { model.moveSection(index - 1) }.disabled(index == 0)
                    Spacer()
                    Text("Reading text · original layout available above").font(.caption).foregroundStyle(LibraryTheme.muted)
                    Spacer()
                    Button("Next section") { model.moveSection(index + 1) }.disabled(index + 1 >= material.sections.count)
                }.padding(16)
            }
        }.background(LibraryTheme.paper)
    }
}

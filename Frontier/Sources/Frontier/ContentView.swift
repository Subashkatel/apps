import AppKit
import SwiftUI
import LocalSupport
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: Model
    var loadsOnAppear = true
    var previewGraphHover: String? = nil
    /// Remembered: which view you were last in is a preference, not a mode you
    /// should have to re-pick every launch.
    private var showGraph: Bool { model.screen == .graph }
    /// Which rendering of the concept you are reading. Remembered, because it
    /// is how you like to read rather than a per-concept choice.
    @AppStorage("frontier.walkthrough") private var walkedThrough = true
    @AppStorage(FrontierAppearance.key) private var appearance = "Dark"
    @AppStorage("frontier.sidebarVisible") private var sidebarVisible = true
    @State private var visitedRead = false
    @State private var visitedGraph = false
    @State private var expandedCourses: Set<String> = []
    @State private var sidebarTitles: [String: String] = [:]
    @State private var courseGroups: [CourseGroup] = []
    @State private var showingImport = false
    @State private var showingAISettings = false

    /// FRONTIER_BARE=1/2/3 — content bisection levels for the compositing hunt.
    private var bareLevel: Int {
        Int(ProcessInfo.processInfo.environment["FRONTIER_BARE"] ?? "0") ?? 0
    }

    var body: some View {
        Group {
            switch bareLevel {
            case 1:
                ConceptPreview(markdown: "# L1\n\nPane alone under the shared modifiers. $x^2$")
            case 2:
                VStack(spacing: 0) {
                    controlBar
                    Divider()
                    ConceptPreview(markdown: "# L2\n\nPane plus control bar. $x^2$")
                }
            case 3:
                HStack(spacing: 0) {
                    sidebar.frame(width: 280)
                    Divider()
                    ConceptPreview(markdown: "# L3\n\nPane plus sidebar. $x^2$")
                }
            default:
                realBody
            }
        }
        .onAppear {
            if loadsOnAppear { FrontierAppearance.apply(appearance); model.load() }
            refreshSidebar()
            visitedRead = model.screen == .read; visitedGraph = model.screen == .graph
            ClickDiagnose.scheduleIfAsked(model: model)
        }
        .onChange(of: model.showingDiscussion) { _, showing in
            if showing { model.pdfReaders.values.forEach { $0.showingNotes = false } }
        }
        .onChange(of: model.concepts) { _, _ in refreshSidebar() }
        .onChange(of: appearance) { _, new in if loadsOnAppear { FrontierAppearance.apply(new) } }
        .onChange(of: model.screen) { _, new in
            if new == .read { visitedRead = true }
            if new == .graph { visitedGraph = true }
        }
        // FRONTIER_OVERLAY=1 — the same renderer, same window, *outside* the
        // split view's detail column. Paints here + blank in the pane = the
        // column; blank here too = the whole window cannot composite it.
        .overlay(alignment: .topTrailing) {
            if ProcessInfo.processInfo.environment["FRONTIER_OVERLAY"] == "1" {
                ConceptPreview(markdown: "# Overlay probe\n\nSame window, outside the detail column. $x^2$")
                    .frame(width: 320, height: 180)
                    .border(.red)
            }
        }
        .sheet(isPresented: $showingAISettings) { AISettingsView() }
        .sheet(isPresented: $showingImport) { ImportSheet(model: model) }
        .alert("Frontier", isPresented: .constant(model.note != nil)) {
            Button("OK") { model.note = nil }
        } message: { Text(model.note ?? "") }
    }

    private var realBody: some View {
        // The controls live in a bar inside the content rather than in a scene
        // toolbar: this window is a plain NSWindow (the SwiftUI Window scene's
        // own window cannot composite a WKWebView on this macOS — see App.swift),
        // and a plain window has no SwiftUI toolbar to put them in.
        VStack(spacing: 0) {
            controlBar
            Divider()
            ZStack {
                LibraryView(model: model, add: { showingImport = true })
                    .opacity(model.screen == .library ? 1 : 0)
                    .allowsHitTesting(model.screen == .library)
                    .accessibilityHidden(model.screen != .library)
                if visitedRead || visitedGraph {
                    HStack(spacing: 0) {
                        if sidebarVisible {
                            sidebar.frame(width: 260)
                            LibraryTheme.rule.frame(width: 1)
                        }
                        ZStack {
                            if visitedRead {
                                HStack(spacing: 0) {
                                    readingWorkspace
                                    if model.showingDiscussion {
                                        FrontierDiscussion(model: model, configure: { showingAISettings = true })
                                            .id(model.discussionID).frame(width: 360)
                                            .overlay(alignment: .leading) { LibraryTheme.rule.frame(width: 1) }
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .opacity(model.screen == .read ? 1 : 0)
                                .allowsHitTesting(model.screen == .read)
                                .accessibilityHidden(model.screen != .read)
                            }
                            if visitedGraph {
                                ConceptGraphView(model: model, isActive: model.screen == .graph, previewHoveredID: previewGraphHover)
                                    .opacity(model.screen == .graph ? 1 : 0)
                                    .allowsHitTesting(model.screen == .graph)
                                    .accessibilityHidden(model.screen != .graph)
                            }
                        }
                    }
                    .opacity(model.screen == .library ? 0 : 1)
                    .allowsHitTesting(model.screen != .library)
                    .accessibilityHidden(model.screen == .library)
                }
            }
        }
        .transaction { $0.animation = nil }
        .font(.system(size: 13))
        .foregroundStyle(LibraryTheme.ink)
        .buttonStyle(LibrarySecondaryButton())
        .background(LibraryTheme.paper)
        .tint(LibraryTheme.accent)
    }

    @ViewBuilder private var learningContent: some View {
        if let explanation = model.passageExplanation { ConceptPreview(markdown: explanation) }
        else if let material = model.readingMaterial {
            if let concept = model.current, model.lessons(for: material).contains(where: { $0.id == concept.id }) { reading(concept) }
            else if let first = model.lessons(for: material).first { reading(first) }
            else { walkthroughStart(material) }
        } else if let concept = model.current { reading(concept) }
        else { empty }
    }
    private var readingWorkspace: some View {
        VStack(spacing: 0) {
            if let item = model.activeMaterial {
                ViewThatFits(in: .horizontal) {
                    HStack { readingControls(item); Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 8) { readingControls(item) }
                }.padding(.horizontal, 18).padding(.vertical, 12)
                Divider()
                if model.readingMode == .source { MaterialSource(model: model, item: item) }
                else if model.readingMode == .compare {
                    HSplitView {
                        learningContent.frame(minWidth: 260, maxWidth: .infinity)
                        MaterialSource(model: model, item: item).frame(minWidth: 380, maxWidth: .infinity)
                    }
                } else if model.readingMode == .walkthrough { learningContent }
                else { MaterialReader(model: model, material: item).id(item.id) }
            } else { learningContent }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func readingControls(_ item: LibraryMaterial) -> some View {
        HStack(spacing: 6) {
            ForEach([Model.ReadingMode.learn, .source, .walkthrough], id: \.self) { mode in
                Button { model.readingMaterialID = item.id; model.readingMode = mode } label: {
                    Text(mode.rawValue).font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(model.readingMode == mode ? LibraryTheme.chrome : .clear, in: .rect(cornerRadius: 5))
                }.buttonStyle(.plain).accessibilityIdentifier("reading-mode-" + (mode == .learn ? "read" : mode == .source ? "source" : "walkthrough"))
                    .accessibilityAddTraits(model.readingMode == mode ? [.isSelected] : [])
            }
            Menu {
                Button("Walkthrough beside original") { model.readingMode = .compare }
                Button("Open original externally") { if let url = MaterialStore.live.existingOriginal(item) { NSWorkspace.shared.open(url) } }
            } label: { Image(systemName: "ellipsis") }.menuIndicator(.hidden).fixedSize().help("Reading options")
        }
    }
    private func walkthroughStart(_ material: LibraryMaterial) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Understand this material").font(.custom("Georgia", size: 28)).accessibilityIdentifier("material-learning-start")
            Text("Build a guided explanation of the concepts, background and notation. Your original remains available to read and annotate.")
                .foregroundStyle(LibraryTheme.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Generate walkthrough lessons") { model.importResource(material.loaded, materialID: material.id) }
                    .disabled(model.busy != nil || material.sections.isEmpty).buttonStyle(LibraryPrimaryButton())
                Button("Ask a question") { model.showingDiscussion = true }.accessibilityIdentifier("material-ask-question")
            }
            Text("Uses your selected AI only when requested.").font(.caption).foregroundStyle(LibraryTheme.muted)
            Spacer()
        }.padding(30).frame(maxWidth: 650, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 18) {
            if model.screen != .library {
                Button { sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help(sidebarVisible ? "Hide sidebar" : "Show sidebar")
                    .accessibilityLabel(sidebarVisible ? "Hide sidebar" : "Show sidebar")
                    .accessibilityIdentifier("toggle-sidebar")
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }
            Spacer()
            HStack(spacing: 3) {
                ForEach(Array(Model.Screen.allCases.enumerated()), id: \.element) { index, screen in
                    Button { model.screen = screen } label: {
                        Text(screen.rawValue).font(.system(size: 12)).padding(.horizontal, 17).padding(.vertical, 6)
                            .background(model.screen == screen ? LibraryTheme.chrome : .clear, in: .rect(cornerRadius: 4))
                    }.buttonStyle(.plain).keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .accessibilityAddTraits(model.screen == screen ? [.isSelected] : [])
                }
            }.padding(3).overlay(RoundedRectangle(cornerRadius: 7).stroke(LibraryTheme.rule, lineWidth: 1))
            Spacer()
            if model.busy != nil {
                ProgressView().controlSize(.small)
                Text(model.importProgress ?? "Working…").font(.caption).lineLimit(1).frame(maxWidth: 180)
            }
            if model.screen == .graph {
                Button("Extend graph") { model.grow() }.disabled(model.busy != nil)
            }
            if model.screen != .library {
                Button { showingImport = true } label: { Image(systemName: "plus") }.help("Add material")
            }
            if model.screen == .read {
                Button(model.showingDiscussion ? "Hide discussion" : "Discuss") { model.showingDiscussion.toggle() }
            }
            AISelectionBadge(load: { try AISettings.load() }, configure: { showingAISettings = true })
                .disabled(model.busy != nil)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 24).padding(.vertical, 13)
        .background(LibraryTheme.paper)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        let today = model.session
        let todayIDs = Set(today.map(\.id))
        let ready = model.ready.filter { !todayIDs.contains($0.id) }
        let known = model.concepts.filter(\.isKnown)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !today.isEmpty {
                    sidebarSection("Today", count: today.count) { ForEach(today) { row($0) } }
                }
                if !ready.isEmpty {
                    sidebarSection("Ready", count: ready.count) { ForEach(ready.prefix(20)) { row($0) } }
                }
                if !courseGroups.isEmpty {
                    sidebarSection("Courses", count: courseGroups.count) {
                        ForEach(courseGroups, id: \.name) { group in
                            LazyVStack(alignment: .leading, spacing: 6) {
                                Button {
                                    if !expandedCourses.insert(group.name).inserted { expandedCourses.remove(group.name) }
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: expandedCourses.contains(group.name) ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 9, weight: .medium)).frame(width: 10).padding(.top, 4)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(group.name).font(.system(size: 12)).lineLimit(3)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text("\(group.done) of \(group.concepts.count) learned")
                                                .font(.system(size: 10)).foregroundStyle(LibraryTheme.muted)
                                        }
                                        Spacer(minLength: 0)
                                    }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityIdentifier("course-" + group.name)
                                    .accessibilityValue(expandedCourses.contains(group.name) ? "Expanded" : "Collapsed")
                                if expandedCourses.contains(group.name) {
                                    ForEach(group.concepts) { row($0) }
                                }
                            }
                        }
                    }
                }
                if !known.isEmpty {
                    sidebarSection("Known", count: known.count) { ForEach(known.prefix(20)) { row($0) } }
                }
            }.padding(.horizontal, 12).padding(.vertical, 22)
        }
        .background(LibraryTheme.paper)
    }

    private func sidebarSection<Content: View>(_ title: String, count: Int,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text("\(count)").font(.system(size: 10)).opacity(0.7)
            }.foregroundStyle(LibraryTheme.muted).padding(.horizontal, 10)
            content()
        }
    }

    private struct CourseGroup {
        let name: String
        let concepts: [Concept]
        let done: Int
    }

    /// Concepts grouped by the course that taught them, in the order they were
    /// added — which for an imported resource is its own reading order, front
    /// to back. Mark what you already know from the top and the frontier walks
    /// the rest of it in sequence.
    private func refreshSidebar() {
        sidebarTitles = Dictionary(uniqueKeysWithValues: model.concepts.map { ($0.id, $0.plainTitle) })
        courseGroups = makeCourseGroups()
    }

    private func makeCourseGroups() -> [CourseGroup] {
        var byCourse: [String: [Concept]] = [:]
        for c in model.concepts {
            for name in c.courses { byCourse[name, default: []].append(c) }
        }
        let hidden = Set(((try? RemovedMaterial.load()) ?? []).map(\.id))
        return byCourse
            .filter { !hidden.contains(LibraryMaterial.courseID($0.key)) }
            .filter { $0.value.count >= 3 }
            .map { name, list in
                let ordered = list.sorted {
                    $0.addedOn == $1.addedOn ? $0.id < $1.id : $0.addedOn < $1.addedOn
                }
                return CourseGroup(name: name, concepts: ordered,
                                   done: list.filter(\.isKnown).count)
            }
            .sorted { $0.concepts.count > $1.concepts.count }
    }

    private func row(_ c: Concept) -> some View {
        let title = sidebarTitles[c.id] ?? c.title
        let selected = model.screen == .graph ? model.graphFocus == c.id : model.selected == c.id && model.readingMaterialID == nil
        return Button {
            if model.screen == .graph { model.selectGraphConcept(c.id) } else { model.openLesson(c) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(selected ? LibraryTheme.accent : colour(c))
                    .frame(width: 5, height: 5).padding(.top, 6)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 12)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(c.area.label).font(.system(size: 10)).foregroundStyle(LibraryTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? LibraryTheme.accent.opacity(0.10) : .clear, in: .rect(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("concept-row-" + c.id)
            .help(title)
    }

    private func colour(_ c: Concept) -> Color {
        switch c.status {
        case .known: return .green
        case .learning: return .orange
        case .unread: return .secondary.opacity(0.5)
        }
    }

    // MARK: - Reading

    private func reading(_ concept: Concept) -> some View {
        // Written entries own their viewport. Introductions are measured into
        // a shared scroll flow so the native action immediately follows them.
        VStack(alignment: .leading, spacing: 0) {
            if !concept.requires.isEmpty {
                Text("rests on " + concept.requires.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 22).padding(.top, 14)
            }

            if model.busy == concept.id {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Writing it, with sources — this takes a minute or two.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if concept.isWritten {
                VStack(alignment: .leading, spacing: 0) {
                    modePicker(concept)
                    ConceptPreview(markdown: document(concept))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // The one flexible child, forced to *accept* the pane's height.
                // Without this the web view reports its full document height —
                // logged at 3,471pt for a 10k-char walkthrough in a 731pt pane —
                // the stack inflates past the window, and the pane shows the
                // empty stretch of an off-screen document: a written concept
                // that reads as a completely blank screen. Same bug, same fix,
                // as PaperNotes' EditorPane; short entries never triggered it,
                // which is why the pane worked until the entries grew.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            } else {
                IntroductionPage(markdown: document(concept)) { unwritten(concept) }


            }

            Divider()
            HStack(spacing: 10) {
                if !concept.sources.isEmpty { sourceSummary(concept) }
                Spacer()
                Menu("Lesson options") {
                    Button("Mark as understood") { model.mark(concept, .known) }.disabled(concept.isKnown)
                    Button("Still learning") { model.mark(concept, .learning) }
                    if concept.isWritten {
                        Divider()
                        Button("Rewrite entry") { model.write(concept) }.disabled(model.busy != nil)
                    }
                }.font(.system(size: 11))
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(LibraryTheme.chrome)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Reference or walkthrough.
    ///
    /// Two renderings of the same facts. The entry is dense on purpose — it is
    /// what you want on the fourth reading. The walkthrough introduces every
    /// term as it appears and shows the arithmetic, which is what you want on
    /// the first, and is the difference between reading a page and understanding
    /// it when the area is new.
    @ViewBuilder
    private func modePicker(_ concept: Concept) -> some View {
        HStack(spacing: 10) {
            if !concept.walkthrough.isEmpty {
                Picker("", selection: $walkedThrough) {
                    Text("Walk me through it").tag(true)
                    Text("Reference").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            } else if model.busy == concept.id {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Working through it from the beginning — a couple of minutes.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                Button { model.explain(concept) } label: {
                    Label("Walk me through it", systemImage: "figure.walk")
                }
                .controlSize(.small)
                .disabled(model.busy != nil)
                .help("Rewrite this assuming no background — every term defined as it "
                    + "appears, every number arrived at, nothing left out")
            }
            Spacer()
            if !concept.walkthrough.isEmpty, model.busy != concept.id {
                Button("Redo") { model.explain(concept) }
                    .controlSize(.small)
                    .disabled(model.busy != nil)
            }
        }
        .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 2)
    }

    /// What "Write it" means, said before it is pressed.
    ///
    /// A concept starts as a title, a reason and its prerequisites; the entry
    /// itself is generated on demand because it costs a minute or two and most
    /// of the graph is there to be navigated, not read.
    private func unwritten(_ concept: Concept) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Ready to explore this concept")
                .font(.system(size: 13, weight: .medium))
            Text("Frontier will ask your selected AI for an explanation at your level — every "
                 + "claim followed by the source it came from, questions to check "
                 + "yourself against, and anything it could not source listed "
                 + "separately rather than smoothed over. Then it checks that each "
                 + "link resolves. A minute or two.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460, alignment: .leading)
            Button {
                model.write(concept)
            } label: {
                Label("Write this entry", systemImage: "text.append")
            }
            .buttonStyle(LibraryPrimaryButton())
            .disabled(model.busy != nil)
            .help(model.busy == nil ? "Generate the entry, with sources"
                                    : "Busy writing something else")
        }
    }

    /// Sources are listed inside the rendered entry; this is the one-line
    /// verdict on whether their links actually resolve.
    private func sourceSummary(_ c: Concept) -> some View {
        let checked = c.sources.filter { $0.reachable != nil }.count
        let broken = c.sources.filter { $0.reachable == false }.count
        return HStack(spacing: 5) {
            Image(systemName: broken > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(broken > 0 ? .orange : .green)
                .font(.system(size: 10))
            Text(broken > 0 ? "\(broken) of \(c.sources.count) links dead"
                            : "\(checked) source\(checked == 1 ? "" : "s") verified")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    /// The shared builder lives on Concept, so `--render` checks exactly what
    /// this pane shows.
    private func document(_ c: Concept) -> String {
        c.document(preferWalkthrough: walkedThrough)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("Nothing in the graph yet.").font(.system(size: 13))
            Text("Frontier --seed <file> turns a list of half-understood terms into a curriculum.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Preview extraction before spending AI usage on a document.
struct ImportSheet: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var preview: Resource.Loaded?
    @State private var reading = false
    @State private var saving = false
    @State private var error: String?

    init(model: Model, previewResource: Resource.Loaded? = nil) {
        self.model = model
        _preview = State(initialValue: previewResource)
        _entry = State(initialValue: previewResource?.origin ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add material").font(.custom("Georgia", size: 26))
            TextField("Web URL or document path", text: $entry).textFieldStyle(.roundedBorder)
            HStack {
                Button("Choose document…") { pick() }
                Button(reading ? "Reading…" : "Preview import") { inspect() }
                    .disabled(reading || entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(ResourceFiles.formatDescription + ", and web pages.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            if let preview {
                Text(preview.name).font(.headline)
                Text("\(preview.sections.count) sections · \(Resource.batches(preview.sections).count) AI requests")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(preview.sections.enumerated()), id: \.offset) { _, section in
                            DisclosureGroup(section.title) {
                                Text(String(section.text.prefix(2000)))
                                    .font(.system(size: 11)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.padding(.trailing, 16)
                }.frame(height: 210)
                Text("Add to library saves the document for reading. Add & generate also sends these sections to your selected AI to create lessons.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Preview reads the document without calling AI. Check the extracted text before importing.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add & generate") { save(generate: true) }
                    .disabled(preview == nil || reading || saving || model.busy != nil)
                Button(saving ? "Adding…" : "Add to library") { save(generate: false) }
                    .buttonStyle(LibraryPrimaryButton()).disabled(preview == nil || reading || saving)
            }
        }
        .padding(22).frame(width: 540).disabled(saving)
        .buttonStyle(LibrarySecondaryButton())
        .background(LibraryTheme.paper).foregroundStyle(LibraryTheme.ink).tint(LibraryTheme.accent)
        .onChange(of: entry) { _, _ in preview = nil; error = nil }
    }

    private func save(generate: Bool) {
        guard let preview else { return }
        saving = true
        Task {
            do {
                let item = try await model.addMaterial(preview)
                if generate { model.importResource(item.loaded, materialID: item.id) }
                model.screen = .library
                dismiss()
            } catch { self.error = error.localizedDescription; saving = false }
        }
    }
    private func inspect() {
        let spec = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        reading = true; error = nil; preview = nil
        Task {
            let result = await Task.detached { Result { try Resource.read(spec) } }.value
            reading = false
            guard entry.trimmingCharacters(in: .whitespacesAndNewlines) == spec else { return }
            switch result {
            case .success(let loaded): preview = loaded
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ResourceFiles.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { entry = url.path }
    }
}

/// A measured renderer and native action share one scroll position. The outer
/// viewport stays bounded even when the introduction is longer than the window.
private struct IntroductionPage<Action: View>: View {
    let markdown: String
    @ViewBuilder var action: () -> Action
    @State private var contentHeight: CGFloat = 180

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { position in
              ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WebPane(markdown: markdown, contentHeightChanged: { contentHeight = $0 })
                        .frame(width: viewport.size.width, height: contentHeight)
                        .id("introduction-top")
                    VStack(alignment: .leading, spacing: 20) {
                        LibraryTheme.rule.frame(height: 1)
                        action()
                    }
                    .frame(maxWidth: 740, alignment: .leading)
                    .padding(.horizontal, 32).padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
              }.frame(width: viewport.size.width, height: viewport.size.height)
                .onChange(of: markdown) { _, _ in position.scrollTo("introduction-top", anchor: .top) }
            }
        }
    }
}

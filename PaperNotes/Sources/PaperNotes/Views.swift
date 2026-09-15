import SwiftUI
import LocalSupport
import UniformTypeIdentifiers

/// Two panes with a draggable divider.
///
/// Deliberately free of GeometryReader: it is greedy in both axes and reports no
/// sensible ideal size, so inside a VStack it shoves its siblings out of the frame —
/// which is what pushed the editor off the top of the window. The left pane carries
/// an explicit width in points and the right one takes what remains, which is plain
/// enough that the parent VStack can lay it out correctly.
struct SplitPane<Left: View, Right: View>: View {
    @Binding var leftWidth: CGFloat
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    @State private var widthAtDragStart: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            left
                .frame(width: leftWidth)
                .frame(maxHeight: .infinity)
                .clipped()
            Divider()
                .overlay(
                    Rectangle().fill(Color.clear)
                        .frame(width: 9)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { g in
                                    let base = widthAtDragStart ?? leftWidth
                                    if widthAtDragStart == nil { widthAtDragStart = leftWidth }
                                    leftWidth = min(1000, max(300, base + g.translation.width))
                                }
                                .onEnded { _ in widthAtDragStart = nil }
                        )
                )
            right
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Window scene ids. `openWindow(id:)` with an id no scene declares fails silently
/// at runtime, and nothing on this machine can drive the UI to catch that — so the
/// two sides are made to share one symbol instead.
enum WindowID {
    static let main = "main"
    static let graph = "graph"
    static let recommend = "recommend"
}

struct OpenWindowButton: View {
    let id: String
    let title: String
    let icon: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: id)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label(title, systemImage: icon)
        }
        .controlSize(.small)
    }
}

/// In the window's own status bar rather than the toolbar — the graph is the point
/// of the app and a menu-only shortcut hid it completely.
struct GraphButton: View {
    var body: some View {
        OpenWindowButton(id: WindowID.graph, title: "Graph", icon: "circle.hexagongrid")
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var editorWidth: CGFloat = 520
    /// The sidebar's selection. Multi-select so the queue action can take several
    /// papers at once; the editor still follows whichever one is the anchor.
    @State private var selection: Set<String> = []
    @State private var query = ""
    @State private var showingAISettings = false

    /// The selection in the order the list shows it, so queuing three papers
    /// reads them top-to-bottom rather than in Set order — which is arbitrary and
    /// would look like the queue shuffled itself.
    private func orderedSelection() -> [String] {
        model.papers.map(\.arxivID).filter { selection.contains($0) }
    }

    var body: some View {
        // The status bar is a sibling in a VStack, not a safeAreaInset on the split
        // view. Applying safeAreaInset to a NavigationSplitView overrides the
        // automatic title-bar safe area that both panes inherit, which ran the
        // sidebar list and the editor 44pt up underneath the title bar — measured,
        // not guessed: ListCoreScrollView reached y=902 against a content rect of 858.
        VStack(spacing: 0) {
            splitView
            Divider()
            statusBar
        }
        .frame(minWidth: 980, minHeight: 600)
        .background(ReviewTheme.surface).tint(ReviewTheme.accent)
        .alert("Could not save the note", isPresented: Binding(
            get: { model.saveError != nil },
            set: { if !$0 { model.saveError = nil } })) {
            Button("OK") { model.saveError = nil }
        } message: {
            Text((model.saveError ?? "") + " Your draft is still in the editor. Resolve the storage problem and save again before switching papers.")
        }
        .sheet(isPresented: $showingAISettings) { PaperAISettingsView() }
        .sheet(isPresented: $model.showingAdd) { AddPaperSheet(model: model) }
        .sheet(isPresented: Binding(get: { model.gradeResult != nil },
                                    set: { if !$0 { model.gradeResult = nil } })) {
            GradeSheet(model: model)
        }
        .alert("Delete this paper?",
               isPresented: Binding(get: { model.confirmDelete != nil },
                                    set: { if !$0 { model.confirmDelete = nil } })) {
            Button("Cancel", role: .cancel) { model.confirmDelete = nil }
            Button("Delete", role: .destructive) {
                if let p = model.confirmDelete { model.delete(p) }
                model.confirmDelete = nil
            }
        } message: {
            Text(model.confirmDelete.map {
                "\"\($0.title.isEmpty ? $0.arxivID : $0.title)\" and its stored PDF will be removed. The note is in git, so it can be recovered from history."
            } ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.ingest(fileURL: url) }
                }
            }
            return true
        }
        .onChange(of: selection) { _, new in
            // One row selected drives the editor; a wider selection leaves the
            // editor where it was rather than flickering between papers.
            if new.count == 1, let id = new.first { model.select(id) }
        }
        .onChange(of: model.selectedID) { _, id in if let id { selection = [id] } }
        .task { model.bootstrap() }
    }

    private var splitView: some View {
        HSplitView {
            VStack(spacing: 12) {
                HStack {
                    TextField("Search papers & notes", text: $query).textFieldStyle(.roundedBorder)
                    Button { model.showingAdd = true } label: { Image(systemName: "plus") }.help("Add paper")
                }.padding(.horizontal, 16).padding(.top, 18)
                if model.isBusy { ProgressView().controlSize(.small) }
                sidebar
            }.frame(minWidth: 250, idealWidth: 270, maxWidth: 340).background(ReviewTheme.surface)
            Group { if model.draft != nil { editor } else { placeholder } }
                .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebar: some View {
        // Multi-select, because queuing is the one action you want to do to
        // several papers at once. A single id still drives the editor; the wider
        // selection only feeds the context menu.
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            Section {
                Picker("Sort", selection: Binding(
                    get: { model.sort },
                    set: { model.sort = $0; model.refresh() })) {
                    ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .labelsHidden()
            }
            if !query.isEmpty {
                let hits = Search.matches(query, in: model.papers)
                Section(hits.isEmpty ? "No matches" : "\(hits.count) match\(hits.count == 1 ? "" : "es")") {
                    ForEach(hits, id: \.paper.arxivID) { hit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.paper.title.isEmpty ? hit.paper.arxivID : hit.paper.title)
                                .font(.system(size: 12)).lineLimit(2)
                            if !hit.snippet.isEmpty {
                                Text(hit.snippet)
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            HStack(spacing: 6) {
                                Text(hit.paper.arxivID).font(.system(size: 9).monospaced())
                                if !hit.field.label.isEmpty {
                                    Text(hit.field.label).font(.system(size: 9))
                                }
                                if hit.paper.archaic {
                                    Text("archived").font(.system(size: 9))
                                }
                            }
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 1)
                        .modifier(ReviewRowSelection(id: hit.paper.arxivID, selection: $selection))
                        .contextMenu { rowMenu(hit.paper) }
                    }
                }
            } else if !model.upNext.isEmpty {
                Section("Up next · \(model.upNext.count)") {
                    ForEach(model.upNext) { p in
                        HStack(spacing: 7) {
                            Text("\(p.queuePosition)")
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 15, height: 15)
                                .background(Circle().fill(Color(hex: 0x2A78D6)))
                            Text(p.title.isEmpty ? p.arxivID : p.title)
                                .font(.system(size: 12)).lineLimit(1)
                        }
                        .modifier(ReviewRowSelection(id: p.arxivID, selection: $selection))
                        .contextMenu {
                            Button("Remove from queue") { model.unqueue([p.arxivID]) }
                            if !p.pdfPath.isEmpty {
                                Button("Open PDF") { model.startReading(p) }
                            }
                        }
                    }
                }
            }
            if query.isEmpty {
            Section("Read · \(model.papers.filter(\.isSubstantive).count) of \(model.papers.count)") {
                ForEach(model.papers) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title.isEmpty ? p.arxivID : p.title)
                            .font(.system(size: 12, weight: p.isSubstantive ? .regular : .light))
                            .foregroundStyle(p.isSubstantive ? .primary : .secondary)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            if p.starred {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color(hex: 0xEDA100))
                            }
                            // Claude's grade until you write your own over it, so the
                            // list is sorted by interest from the moment a paper
                            // lands rather than only after you have read it.
                            if p.effectiveVerdict != .unset {
                                Text(p.effectiveVerdict.label)
                                    .font(.system(size: 8, weight: .semibold))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Capsule().fill(
                                        p.verdict == .unset ? AnyShapeStyle(.quinary)
                                                            : AnyShapeStyle(.quaternary)))
                            }
                            if model.appraising.contains(p.arxivID) {
                                ProgressView().controlSize(.small).scaleEffect(0.4)
                                    .frame(width: 10, height: 10)
                            }
                            Text(p.arxivID).font(.system(size: 9).monospaced())
                            if !p.refs.isEmpty { Text("\(p.refs.count) refs").font(.system(size: 9)) }
                            if !p.pdfPath.isEmpty { Image(systemName: "doc").font(.system(size: 8)) }
                        }
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .modifier(ReviewRowSelection(id: p.arxivID, selection: $selection))
                    .contextMenu { rowMenu(p) }
                }
            }
            }
        }
          }.padding(14)
        .background(ReviewTheme.surface)
        .frame(minWidth: 250)
    }

    /// Shared by the library list and the search results, so an action available
    /// on a paper does not depend on how you found it.
    @ViewBuilder
    private func rowMenu(_ p: Paper) -> some View {
        // Acts on the whole selection when this row is part of it, so
        // right-clicking one of five selected papers queues all five rather than
        // silently just the one under the cursor.
        let targets = selection.contains(p.arxivID) ? orderedSelection() : [p.arxivID]
        if p.isQueued {
            Button("Remove from queue") { model.unqueue(targets) }
        } else {
            Button(targets.count > 1 ? "Read these \(targets.count) next" : "Read next") {
                model.queue(targets)
            }
            Button("Add to end of queue") { model.queue(targets, atFront: false) }
        }
        Divider()
        Button(p.starred ? "Remove star" : "Star this paper") { model.toggleStar(p) }
        if !p.pdfPath.isEmpty {
            Button("Open PDF") { model.startReading(p) }
        }
        Divider()
        // Destructive, and it takes the stored PDF with it, so it asks first
        // rather than relying on undo that does not exist.
        Button("Delete…", role: .destructive) { model.confirmDelete = p }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(.tertiary)
            Text("Add a paper to begin").foregroundStyle(.secondary)
            Text("Drop a PDF here, or right-click one in Finder →\nServices → Add to Paper Notes.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var editor: some View {
        EditorPane(model: model, leftWidth: $editorWidth)
    }
}

/// Extracted so it can be rendered offscreen on its own. ImageRenderer cannot draw a
/// NavigationSplitView — it needs a real window and rasterises as a prohibition
/// glyph — but it renders ordinary SwiftUI content faithfully, which makes this the
/// only way to actually see a layout on a machine without screen-recording access.
struct EditorPane: View {
    @Bindable var model: AppModel
    @Binding var leftWidth: CGFloat

    @AppStorage("reviewMode") private var mode = "Preview"
    @State private var toolsExpanded = false
    @State private var connectionsExpanded = false
    @State private var showingAISettings = false
    private var reviewModePicker: some View {
        Picker("View", selection: $mode) {
            Text("Write").tag("Write"); Text("Preview").tag("Preview"); Text("Split").tag("Split")
        }.pickerStyle(.segmented).labelsHidden()
    }
    var body: some View {
        if let draft = model.draft {
            HStack(spacing: 0) {
            VStack(spacing: 0) {
                NoteHeader(model: model, paper: draft).padding(.horizontal, 28).padding(.vertical, 20)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("My review").font(.custom("Georgia", size: 17)).fixedSize()
                        Spacer()
                        Button(model.showingDiscussion ? "Hide discussion" : "Discuss") { model.showingDiscussion.toggle() }
                            .fixedSize().accessibilityIdentifier("toggle-discussion")
                        if !model.showingDiscussion { reviewModePicker.frame(width: 235) }
                    }
                    if model.showingDiscussion { reviewModePicker }
                }.padding(.horizontal, 28).padding(.vertical, 12)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        if mode != "Preview" {
                            TextEditor(text: Binding(get: { model.draft?.body ?? "" }, set: { model.draft?.body = $0 }))
                                .font(.system(size: 14, design: .monospaced)).lineSpacing(4)
                                .scrollContentBackground(.hidden).padding(16)
                                .frame(width: mode == "Split" ? geometry.size.width * 0.5 : geometry.size.width)
                                .accessibilityIdentifier("review-editor")
                        }
                        if mode == "Split" { Divider() }
                        MarkdownPreview(markdown: draft.body)
                            .frame(width: mode == "Write" ? 0 : mode == "Split" ? geometry.size.width * 0.5 - 1 : geometry.size.width)
                            .opacity(mode == "Write" ? 0 : 1).allowsHitTesting(mode != "Write")
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(1)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup("Prompts & review tools", isExpanded: $toolsExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Menu("Add a review prompt") { ForEach(ReviewPrompt.allCases, id: \.self) { prompt in Button(prompt.rawValue) { model.appendPrompt(prompt) } } }
                                Spacer()
                                if model.isGrading { ProgressView().controlSize(.small) }
                                Button("Grade my note") { model.gradeCurrentNote() }.disabled(model.isGrading || !draft.isSubstantive)
                            }
                            NoteHeader(model: model, paper: draft).appraisalRow
                        }.padding(.top, 10)
                    }
                    DisclosureGroup("Connections · \(model.related.count)", isExpanded: $connectionsExpanded) {
                        ReviewConnections(model: model).padding(.top, 10)
                    }
                }.font(.system(size: 12)).padding(.horizontal, 28).padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ReviewTheme.surface).tint(ReviewTheme.accent)
            if model.showingDiscussion {
                PaperDiscussion(model: model, paper: draft, close: { model.showingDiscussion = false }, configure: { showingAISettings = true })
                    .id(draft.arxivID).frame(width: 370)
                    .overlay(alignment: .leading) { Divider() }
            }
            }.sheet(isPresented: $showingAISettings) { PaperAISettingsView() }
        }
    }
}

extension ContentView {
    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(model.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if model.unpushed > 0 {
                Text("\(model.unpushed) unpushed").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Toggle("Push to Git remote", isOn: Binding(
                get: { Prefs.pushEnabled },
                set: { Prefs.pushEnabled = $0; if $0 { model.pushIfEnabled() } }))
                .toggleStyle(.checkbox)
                .font(.system(size: 10))
            AISelectionBadge(load: { try PaperAI.load() }, configure: { showingAISettings = true })
            GraphButton()
            OpenWindowButton(id: WindowID.recommend, title: "Next", icon: "sparkles")
            Button("Save") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(ReviewTheme.surface)
    }
}

struct NoteHeader: View {
    @Bindable var model: AppModel
    let paper: Paper

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(paper.title.isEmpty ? paper.arxivID : paper.title)
                .font(.custom("Georgia", size: 26)).lineLimit(2)
                .frame(height: 66, alignment: .topLeading)
            HStack(spacing: 8) {
                Text(paper.authors.prefix(3).joined(separator: ", ")).lineLimit(1)
                if let year = paper.year { Text(String(year)) }
                if let url = paper.externalURL { Link(paper.externalLinkLabel, destination: url) }
                Spacer()
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Picker("My take", selection: Binding(get: { model.draft?.verdict ?? .unset }, set: { model.draft?.verdict = $0 })) {
                    ForEach(Verdict.allCases, id: \.self) { Text($0 == .unset ? "Not rated" : $0.rawValue.capitalized).tag($0) }
                }.pickerStyle(.menu).frame(width: 180)
                Button { model.toggleStar(paper) } label: { Image(systemName: paper.starred ? "star.fill" : "star") }
                    .buttonStyle(.plain).help("Star this paper")
                Spacer()
                if paper.resolvedPDF != nil { Button("Open PDF ↗") { model.startReading(paper) } }
                else { Button("Attach PDF…") { model.attachPDF(paper) }.accessibilityIdentifier("attach-pdf") }
            }.controlSize(.small)
        }
    }
}

extension NoteHeader {
    /// Claude's read on whether the idea is worth your time — graded on how
    /// surprising and generative it is, not on how carefully it was executed.
    @ViewBuilder
    var appraisalRow: some View {
        HStack(spacing: 6) {
            if model.appraising.contains(paper.arxivID) {
                ProgressView().controlSize(.small).scaleEffect(0.55)
                    .frame(width: 12, height: 12)
                Text("AI is reading it…")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            } else if paper.appraisal != .unset {
                Text("AI appraisal: \(paper.appraisal.label)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                // The position is the honest part. The band is only a coarsening of
                // it, and a band assigned without ranking meant almost nothing.
                if paper.appraisalRank > 0 {
                    Text("#\(paper.appraisalRank) of \(model.papers.filter { $0.appraisalRank > 0 }.count)")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Text(paper.appraisalNote)
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.tail)
                    // The full sentence is in the note file either way; the tooltip
                    // saves opening it.
                    .help(paper.appraisalNote)
                if paper.overridesAppraisal {
                    Text("· you said \(paper.verdict.label)")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            } else if !paper.pdfPath.isEmpty && Judge.isAvailable {
                Button("Ask AI about this paper") { model.appraise(paper) }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }
            Spacer()
        }
    }
}

/// The point of the whole thing: after writing, you are shown what this connects to.
private struct RelatedPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Connected to what you've read")
                .font(.system(size: 11, weight: .medium))
            if model.related.isEmpty {
                Text("Nothing yet — the graph fills in as you add papers that cite each other.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            } else {
                // Fixed height, and fixed-height cards inside it. A horizontal
                // ScrollView is still flexible *vertically*, which made this a second
                // greedy child in a VStack that already has one — and its content
                // height changes with the selection, so the layout shifted whenever a
                // different paper was clicked.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.related) { r in
                            Button { model.select(r.other.arxivID) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.explanation)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text(r.other.title.isEmpty ? r.other.arxivID : r.other.title)
                                        .font(.system(size: 11))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .frame(width: 190, height: 38, alignment: .topLeading)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.quinary))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 54)
            }
        }
        // A constant height whether or not there are relations. Otherwise the strip
        // is 54pt for a connected paper and one line of text for an unconnected one,
        // and everything above it jumps by ~41pt each time the selection changes —
        // measured across the library before this was fixed.
        .frame(maxWidth: .infinity, minHeight: 73, maxHeight: 73, alignment: .topLeading)
    }
}

private struct AddPaperSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var pdf: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a paper").font(.system(size: 14, weight: .semibold))
            TextField("arXiv id or URL — e.g. 2510.23966", text: $entry)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button("Choose PDF…") { pick() }
                if let pdf {
                    Text(pdf.lastPathComponent).font(.system(size: 10)).lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            Text("A PDF is what gives you citation edges — the free APIs return no references for recent preprints. It also opens for reading straight away.")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    let e = entry, p = pdf
                    Task { await model.add(idOrURL: e.isEmpty ? (p?.lastPathComponent ?? "") : e, pdf: p) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(entry.isEmpty && pdf == nil)
            }
        }
        .padding(18)
        .frame(width: 440)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { pdf = panel.url }
    }
}

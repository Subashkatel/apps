import AppKit
import SwiftUI

/// The curriculum as a picture.
///
/// Same force layout as the paper graph, different meaning on the edges: here
/// an edge is "rests on", so the shape of the drawing is the order you have to
/// learn things in. Colour is status, so at a glance the green region is what
/// you have, the ringed nodes are the frontier, and the faint ones are still
/// behind something.
struct ConceptGraphView: View {
    @ObservedObject var model: Model
    var isActive = true
    var previewHoveredID: String? = nil
    @Environment(\.colorScheme) private var scheme

    @State private var sim = GraphSim()
    @State private var canvas: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var magnifyBase: CGFloat = 1
    @State private var hovered: String?
    @State private var ticker: Timer?
    @State private var gesture = ViewportGesture()
    @State private var scrollMonitor: Any?
    private struct Topology: Equatable {
        var ids: [String]
        var prerequisites: [[String]]
    }
    @State private var loadedTopology: Topology?
    @State private var layoutTask: Task<Void, Never>?
    @State private var layoutRequest = UUID()
    @State private var arranging = false
    @State private var visible = false
    @State private var viewportFrame: CGRect = .zero
    @State private var byID: [String: Concept] = [:]
    @State private var labels: [String: String] = [:]
    @State private var edges: [(String, String, Double)] = []

    /// Derived graph data, cached across frames.
    ///
    /// The Canvas redraws sixty times a second while the simulation settles, and
    /// this used to be recomputed inside the *node loop* of every frame —
    /// measured with --bench at 275 concepts, one frame cost 2,511 ms, which is
    /// "clicking the graph button overloads the PC" stated precisely. Statuses
    /// and edges cannot change while the graph is on screen (marking happens in
    /// the reading pane), so refreshing on appear and on concept-count change is
    /// both correct and ~0 per frame.
    @State private var unlockCounts: [String: Int] = [:]
    @State private var readyIDs: Set<String> = []
    @State private var importanceRank: [String: Int] = [:]   // 0 = biggest bottleneck
    @State private var dependantsMap: [String: [String]] = [:]

    private func refreshDerived() {
        byID = Dictionary(uniqueKeysWithValues: model.concepts.map { ($0.id, $0) })
        labels = Dictionary(uniqueKeysWithValues: model.concepts.map { ($0.id, $0.shortTitle) })
        let present = Set(byID.keys)
        edges = model.concepts.flatMap { c in c.requires.filter(present.contains).map { (c.id, $0, 1.0) } }
        unlockCounts = Frontier.unlocks(model.concepts)
        readyIDs = Set(Frontier.ready(model.concepts).map(\.id))
        let ranked = model.concepts.sorted {
            let l = unlockCounts[$0.id] ?? 0, r = unlockCounts[$1.id] ?? 0
            return l == r ? $0.id < $1.id : l > r
        }
        importanceRank = Dictionary(uniqueKeysWithValues:
            ranked.enumerated().map { ($0.element.id, $0.offset) })
        var dependants: [String: [String]] = [:]
        for c in model.concepts {
            for r in c.requires { dependants[r, default: []].append(c.id) }
        }
        dependantsMap = dependants
    }

    /// How many nodes are drawn in full at this zoom. The graph simplifies
    /// itself when zoomed out — the bottlenecks and anything actionable stay,
    /// the long tail becomes specks — and fills back in as you zoom.
    private var detailBudget: Int { max(30, Int(80 * scale * scale)) }

    private var surface: Color { LibraryTheme.paper }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in draw(in: context, size: size) }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p): hovered = node(at: world(p, in: canvas)); model.graphFocus = hovered
                        case .ended: hovered = nil; model.graphFocus = nil
                        }
                    }
                    .gesture(dragGesture)
                    .gesture(MagnifyGesture()
                        .onChanged { v in scale = min(4, max(0.25, magnifyBase * v.magnification)) }
                        .onEnded { _ in magnifyBase = scale })

                if arranging {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Arranging the graph…").font(.caption) }
                        .padding(12).background(LibraryTheme.chrome, in: .rect(cornerRadius: 6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                legend
                controls
                // Keep one warm renderer as the pointer moves between nodes.
                GraphHoverCard(concept: hovered.flatMap { byID[$0] })
                    .padding(.top, 48).padding(.leading, 12)
                    .opacity(hovered == nil ? 0 : 1)
                    .allowsHitTesting(false).accessibilityHidden(hovered == nil)
                if model.concepts.isEmpty {
                    Text("Nothing in the graph yet.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                visible = isActive
                hovered = previewHoveredID; model.graphFocus = previewHoveredID
                refreshDerived(); canvas = geo.size; viewportFrame = geo.frame(in: .global)
                reload(geo.size)
                if isActive { startTicking(); installScrollZoom() }
            }
            .onDisappear { visible = false; ticker?.invalidate(); ticker = nil; removeScrollZoom(); layoutTask?.cancel() }
            .onChange(of: isActive) { _, active in
                visible = active
                if active { hovered = nil; model.graphFocus = nil; startTicking(); installScrollZoom() }
                else { ticker?.invalidate(); ticker = nil; removeScrollZoom(); hovered = nil }
            }
            .onChange(of: geo.size) { _, new in canvas = new; viewportFrame = geo.frame(in: .global); reload(new) }
            .onChange(of: model.graphFocus) { _, id in hovered = id }
            .onChange(of: model.concepts) { _, _ in refreshDerived(); reload(geo.size) }
        }
        .background(surface)
    }

    // MARK: - Layout

    private func reload(_ size: CGSize, force: Bool = false) {
        guard size.width > 0 else { return }
        let topology = Topology(ids: model.concepts.map(\.id), prerequisites: model.concepts.map(\.requires))
        var masses: [String: Double] = [:]
        for c in model.concepts { masses[c.id] = 1 + Double(unlockCounts[c.id] ?? 0) }
        if !force, loadedTopology == topology {
            sim.updateMasses(masses)
            return
        }
        loadedTopology = topology
        let ids = model.concepts.map(\.id), links = edges, weights = masses
        layoutTask?.cancel()
        let request = UUID(); layoutRequest = request; arranging = true
        layoutTask = Task { @MainActor in
            let started = Date()
            let worker = Task.detached(priority: .userInitiated) {
                ForceLayout.layout(ids: ids, edges: links, size: size)
            }
            let positions = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled, layoutRequest == request else { return }
            sim.load(ids: ids, edges: links, masses: weights, size: size, seeded: positions, settled: true, preservePositions: false)
            if previewHoveredID != nil { print("Graph arranged and settled: \(Int(Date().timeIntervalSince(started) * 1000)) ms") }
            arranging = false
            if visible { startTicking() }
        }
    }

    private func startTicking() {
        guard visible, ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard visible, !sim.isSettled else { timer.invalidate(); ticker = nil; return }
                sim.step(centre: CGPoint(x: canvas.width / 2, y: canvas.height / 2))
            }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Screen point → graph coordinates. Centre-anchored, so zooming magnifies
    /// what you are looking at rather than the top-left corner.
    private func world(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(x: cx + (p.x - cx - pan.width) / scale,
                       y: cy + (p.y - cy - pan.height) / scale)
    }

    private func screen(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(x: cx + (p.x - cx) * scale + pan.width,
                       y: cy + (p.y - cy) * scale + pan.height)
    }

    /// Drag to pan, or drag a node to move it.
    ///
    /// `began()` records the origin once; my first attempt added the gesture's
    /// cumulative translation to the pan on every frame, which accelerated the
    /// graph off screen instead of following the cursor.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                gesture.began(hit: node(at: world(value.startLocation, in: canvas)),
                              currentPan: pan)
                if let id = gesture.draggedNode {
                    if model.selected != id || model.readingMaterialID != nil { model.selectGraphConcept(id) }
                    if hypot(value.translation.width, value.translation.height) > 2 {
                        sim.dragging = id
                        sim.dragTarget = world(value.location, in: canvas)
                        sim.reheat(); startTicking()
                    }
                } else if gesture.isPanning {
                    pan = gesture.pan(for: value.translation)
                }
            }
            .onEnded { _ in
                let movedNode = sim.dragging != nil
                gesture.ended()
                sim.dragging = nil
                if movedNode { sim.reheat(0.35); startTicking() }
            }
    }

    /// Scroll-wheel zoom. SwiftUI has no scroll modifier on macOS, and a *local*
    /// NSEvent monitor sees only this app's events, so it needs no permission.
    private func installScrollZoom() {
        removeScrollZoom()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isActive, let window = event.window, window.attachedSheet == nil,
                  let content = window.contentView,
                  viewportFrame.contains(CGPoint(x: event.locationInWindow.x, y: content.bounds.height - event.locationInWindow.y)) else { return event }
            let factor = exp(event.scrollingDeltaY * 0.006)
            scale = min(4, max(0.25, scale * factor))
            magnifyBase = scale
            return nil
        }
    }

    private func removeScrollZoom() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    private func node(at p: CGPoint) -> String? {
        sim.bodies.min { a, b in
            hypot(a.value.position.x - p.x, a.value.position.y - p.y) < hypot(b.value.position.x - p.x, b.value.position.y - p.y)
        }.flatMap { id, body in
            hypot(body.position.x - p.x, body.position.y - p.y) < 16 / max(1, scale) ? id : nil
        }
    }

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, size: CGSize) {
        let ready = readyIDs

        // Once per frame, not per node — the per-node version of this is the
        // 2.5-second frame --bench measured.
        let neighbours: Set<String> = hovered.map { h in
            Set((byID[h]?.requires ?? []) + (dependantsMap[h] ?? []))
        } ?? []

        // Level of detail. Zoomed out, the graph simplifies itself: the biggest
        // bottlenecks and everything actionable — ready, started, known, under
        // the pointer — draw in full, and the long tail is a speck field that
        // keeps the shape without the noise. Zooming in raises the budget until
        // everything is back.
        let budget = detailBudget
        var detailed: Set<String> = []
        for id in sim.bodies.keys {
            guard let c = byID[id] else { continue }
            if c.status != .unread || ready.contains(id)
                || id == hovered || neighbours.contains(id) || id == model.graphFocus
                || (importanceRank[id] ?? .max) < budget {
                detailed.insert(id)
            }
        }

        for (from, to, _) in edges {
            guard let a = sim.bodies[from]?.position, let b = sim.bodies[to]?.position else { continue }
            var path = Path()
            path.move(to: screen(a, in: size))
            path.addLine(to: screen(b, in: size))
            // An edge into something you know is settled; one into something you
            // do not is the part of the map still to walk. An edge with a speck
            // on either end is only a hint of structure.
            guard detailed.contains(from), detailed.contains(to) else {
                context.stroke(path, with: .color(.secondary.opacity(0.05)), lineWidth: 0.5)
                continue
            }
            let solid = byID[to]?.isKnown == true
            context.stroke(path, with: .color(.secondary.opacity(solid ? 0.35 : 0.14)),
                           lineWidth: solid ? 1 : 0.7)
        }

        for (id, body) in sim.bodies {
            guard let c = byID[id] else { continue }
            let p = screen(body.position, in: size)

            guard detailed.contains(id) else {
                let dot = CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)
                context.fill(Path(ellipseIn: dot), with: .color(.secondary.opacity(0.22)))
                continue
            }

            let r = 5 + min(9, sqrt(Double(unlockCounts[id] ?? 0)) * 3)
            let box = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            switch c.status {
            case .known:
                context.fill(Path(ellipseIn: box), with: .color(.green.opacity(0.85)))
            case .learning:
                context.fill(Path(ellipseIn: box), with: .color(.orange.opacity(0.85)))
            case .unread:
                if ready.contains(id) {
                    // Ringed, not filled: available, not yet taken.
                    context.stroke(Path(ellipseIn: box), with: .color(LibraryTheme.accent), lineWidth: 2)
                } else {
                    context.fill(Path(ellipseIn: box), with: .color(.secondary.opacity(0.25)))
                }
            }
            // Labels are rationed. Everything you can act on is named — what is
            // ready, what you already know, whatever is under the pointer and
            // whatever it depends on — and the rest of the graph stays shape
            // until you zoom into it. Forty labels at once is a wall of text
            // with a graph hidden behind it.
            let named = id == hovered || neighbours.contains(id)
                || ready.contains(id) || c.isKnown || scale > 1.6
            if named {
                context.draw(Text(labels[id] ?? c.title)
                    .font(.system(size: 9, weight: id == hovered ? .semibold : .regular))
                    .foregroundStyle(id == hovered ? AnyShapeStyle(.primary)
                                                   : AnyShapeStyle(.secondary)),
                             at: CGPoint(x: p.x, y: p.y + r + 8))
            }
        }
    }

    /// Told, not discovered. Pan and zoom have no affordance on a canvas — the
    /// first version had neither working and nothing on screen said they were
    /// meant to, so there was no way to tell a broken gesture from a missing
    /// feature.
    private var controls: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Text("drag to pan · scroll to zoom · drag a concept to move it")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                Spacer()
                Button { zoom(1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                Button { zoom(0.8) } label: { Image(systemName: "minus.magnifyingglass") }
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { scale = 1; pan = .zero }
                    magnifyBase = 1
                    reload(canvas, force: true)
                } label: { Image(systemName: "arrow.counterclockwise") }
                    .help("Reset the view and re-settle the graph")
            }
            .buttonStyle(LibrarySecondaryButton())
            .controlSize(.small)
        }
        .padding(12)
    }

    private func zoom(_ factor: CGFloat) {
        withAnimation(.easeOut(duration: 0.15)) { scale = min(4, max(0.25, scale * factor)) }
        magnifyBase = scale
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([("Known", Color.green), ("Learning", .orange), ("Ready", LibraryTheme.accent),
                     ("Behind a prerequisite", .secondary.opacity(0.4))], id: \.0) { name, colour in
                HStack(spacing: 4) {
                    Circle().fill(colour).frame(width: 6, height: 6)
                    Text(name).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Told, not discovered: when the zoom level is hiding detail, the
            // legend says so, so a field of specks reads as "zoom in" rather
            // than "broken".
            if detailBudget < model.concepts.count {
                Text("simplified — zoom in for the rest")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Text("\(model.concepts.count) concepts · \(edges.count) prerequisites")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(12)
    }

}

/// The same bundled Markdown/KaTeX engine as Read, sized for a graph preview.
struct GraphHoverCard: View {
    let concept: Concept?
    @State private var height: CGFloat = 120
    var body: some View {
        let markdown = concept.map { "# " + $0.title + "\n\n" + $0.relevance } ?? " "
        WebPane(markdown: markdown, contentHeightChanged: { height = $0 }, presentation: .card)
            .frame(width: 350, height: min(360, max(60, height)))
            .clipShape(.rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(LibraryTheme.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
}

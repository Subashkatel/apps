import Foundation
import CoreGraphics

/// Fruchterman–Reingold with gravity, then normalised to fit the canvas.
///
/// Deterministic: initial positions come from a hash of the paper id, not a random
/// generator, so the same library always lays out the same way. A graph that
/// rearranges itself every time you open it is one you can never learn.
///
/// The earlier version clamped positions to the canvas during the simulation. With a
/// small library `k = sqrt(area/n)` is larger than the canvas itself, so every node
/// pushed outward, hit the clamp and stuck there — the whole graph pressed flat
/// against the walls with nothing in the middle. The simulation now runs unbounded
/// and the result is scaled to fit afterwards, which is what makes the spacing
/// independent of how many papers there are.
enum ForceLayout {
    struct Node {
        let id: String
        var position: CGPoint
        var degree: Int = 0
    }

    private static func hashUnit(_ s: String, salt: UInt64) -> Double {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325 ^ salt
        for byte in s.utf8 { h = (h ^ UInt64(byte)) &* 0x1000_0000_01b3 }
        return Double(h % 10_000) / 10_000.0
    }

    static func layout(ids: [String],
                       edges: [(String, String, Double)],
                       size: CGSize,
                       iterations: Int = 400) -> [String: Node] {
        guard !ids.isEmpty else { return [:] }
        guard ids.count > 1 else {
            return [ids[0]: Node(id: ids[0],
                                 position: CGPoint(x: size.width / 2, y: size.height / 2))]
        }

        // Simulation happens in an abstract unit space; the canvas only matters at
        // the end, when the result is scaled into it.
        // Dense indices keep string hashing and dictionary copies out of the
        // quadratic force loop. Each pair contributes equal/opposite forces.
        let indices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        var positions: [CGPoint] = ids.enumerated().map { i, id in
            let angle = Double(i) / Double(ids.count) * 2 * .pi
            let radius = 100 * (0.75 + hashUnit(id, salt: 11) * 0.5)
            return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
        var degree: [String: Int] = [:]
        var links: [(Int, Int, Double)] = []
        for (a, b, weight) in edges {
            guard let i = indices[a], let j = indices[b] else { continue }
            degree[a, default: 0] += 1; degree[b, default: 0] += 1
            links.append((i, j, weight))
        }
        let k = 90.0
        var temperature = 60.0
        for _ in 0..<max(0, iterations) {
            if Task.isCancelled { return [:] }
            var displacement = positions.map { CGPoint(x: -$0.x * 0.75, y: -$0.y * 0.75) }
            for i in positions.indices {
                for j in (i + 1)..<positions.count {
                    var dx = positions[i].x - positions[j].x
                    var dy = positions[i].y - positions[j].y
                    var distanceSquared = dx * dx + dy * dy
                    if distanceSquared < 0.0001 {
                        dx = hashUnit(ids[i], salt: 3) - 0.5
                        dy = hashUnit(ids[j], salt: 5) - 0.5
                        distanceSquared = max(0.0001, dx * dx + dy * dy)
                    }
                    let force = k * k / distanceSquared
                    let fx = dx * force, fy = dy * force
                    displacement[i].x += fx; displacement[i].y += fy
                    displacement[j].x -= fx; displacement[j].y -= fy
                }
            }
            for (i, j, weight) in links {
                let dx = positions[i].x - positions[j].x, dy = positions[i].y - positions[j].y
                let distance = max(0.01, hypot(dx, dy))
                let force = distance / k * (0.5 + weight)
                let fx = dx * force, fy = dy * force
                displacement[i].x -= fx; displacement[i].y -= fy
                displacement[j].x += fx; displacement[j].y += fy
            }
            for i in positions.indices {
                let d = displacement[i]
                let magnitude = max(0.0001, hypot(d.x, d.y))
                let factor = min(magnitude, temperature) / magnitude
                let next = CGPoint(x: positions[i].x + d.x * factor, y: positions[i].y + d.y * factor)
                if next.x.isFinite && next.y.isFinite { positions[i] = next }
            }
            temperature = max(0.05, temperature * 0.985)
        }
        let pos = Dictionary(uniqueKeysWithValues: zip(ids, positions))

        return fit(pos, degree: degree, into: size)
    }

    /// Scales the settled layout into the canvas, preserving aspect so clusters keep
    /// their shape. Padding leaves room for the labels drawn beneath each node.
    private static func fit(_ pos: [String: CGPoint],
                            degree: [String: Int],
                            into size: CGSize) -> [String: Node] {
        let xs = pos.values.map { Double($0.x) }, ys = pos.values.map { Double($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return [:] }

        let padX = 70.0, padY = 54.0
        let availableW = max(1, Double(size.width) - padX * 2)
        let availableH = max(1, Double(size.height) - padY * 2)
        let spanX = max(1e-6, maxX - minX), spanY = max(1e-6, maxY - minY)
        let scale = min(availableW / spanX, availableH / spanY)

        // Centre whatever the scale leaves over, so the graph sits in the middle
        // rather than hugging one edge.
        let usedW = spanX * scale, usedH = spanY * scale
        let offsetX = padX + (availableW - usedW) / 2
        let offsetY = padY + (availableH - usedH) / 2

        var out: [String: Node] = [:]
        for (id, p) in pos {
            let x = (Double(p.x) - minX) * scale + offsetX
            let y = (Double(p.y) - minY) * scale + offsetY
            out[id] = Node(id: id, position: CGPoint(x: x, y: y), degree: degree[id] ?? 0)
        }
        return out
    }
}

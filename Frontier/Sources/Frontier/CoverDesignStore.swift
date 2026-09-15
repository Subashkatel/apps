import Foundation

/// A library-wide allocation ledger, not a random per-item choice from a small pool.
/// Entries are retained after removal, so restoring or adding material never swaps art.
struct CoverDesignStore {
    let file: URL
    func assign(_ ids: [String]) throws -> [String: Int] {
        var assignments: [String: Int] = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            assignments = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: file))
            guard assignments.values.allSatisfy({ $0 >= 0 && $0 < Int.max }), Set(assignments.values).count == assignments.count else {
                throw FrontierError("The saved cover assignments are invalid; they have not been replaced.")
            }
        }
        let oldCount = assignments.count
        var next = (assignments.values.max() ?? -1) + 1
        for id in ids where assignments[id] == nil {
            assignments[id] = next; next += 1
        }
        if assignments.count != oldCount {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(assignments).write(to: file, options: .atomic)
        }
        return assignments
    }
}

/// Stable ordered compositions: distinct single motifs first, then combinations.
/// The ledger ordinal remains unchanged across design updates and library edits.
struct CoverComposition: Hashable {
    let layout = 0
    let illustrations: [Int]
    init(index: Int) {
        var sequence = [index % 24], remainder = index / 24
        while remainder > 0 {
            sequence.append((remainder - 1) % 24)
            remainder = (remainder - 1) / 24
        }
        illustrations = sequence
    }
}

/// Fit the illustration as one piece. Never stretch x and y independently.
struct CoverArtworkPlacement {
    let frame: CGRect
    let scale: CGFloat
    let rotated: Bool
    init(in bounds: CGRect, rotated: Bool) {
        self.rotated = rotated
        let size = rotated ? CGSize(width: 83, height: 190) : CGSize(width: 190, height: 83)
        scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        frame = CGRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
                       width: fitted.width, height: fitted.height)
    }
}

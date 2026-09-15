import SwiftUI

struct AccountFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// The insertion slot is measured in the full list, then adjusted for removal.
enum AccountReordering {
    static func slot(at y: CGFloat, ids: [String], frames: [String: CGRect]) -> Int? {
        guard !ids.isEmpty, ids.allSatisfy({ frames[$0] != nil }) else { return nil }
        return ids.firstIndex { y < frames[$0]!.midY } ?? ids.count
    }

    static func destination(source: Int, slot: Int, count: Int) -> Int? {
        guard (0..<count).contains(source), (0...count).contains(slot) else { return nil }
        return slot > source ? slot - 1 : slot
    }

    static func scrollTarget(at y: CGFloat, height: CGFloat, ids: [String], frames: [String: CGRect]) -> String? {
        if y > height - 32 {
            return ids.first { (frames[$0]?.maxY ?? 0) > height + 1 }
        }
        if y < 32 {
            return ids.last { (frames[$0]?.minY ?? 0) < -1 }
        }
        return nil
    }
}

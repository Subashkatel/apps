import AppKit

/// Names describe colors, leaving their meaning to the reader.
enum HighlightColor: String, CaseIterable {
    case yellow = "Yellow", red = "Red", green = "Green", blue = "Blue", purple = "Purple"
    var color: NSColor {
        switch self {
        case .yellow: NSColor(srgbRed: 0.93, green: 0.75, blue: 0.23, alpha: 1)
        case .red: NSColor(srgbRed: 0.93, green: 0.37, blue: 0.36, alpha: 1)
        case .green: NSColor(srgbRed: 0.36, green: 0.72, blue: 0.43, alpha: 1)
        case .blue: NSColor(srgbRed: 0.33, green: 0.64, blue: 0.91, alpha: 1)
        case .purple: NSColor(srgbRed: 0.71, green: 0.49, blue: 0.85, alpha: 1)
        }
    }
}

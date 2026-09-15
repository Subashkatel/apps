import AppKit
import SwiftUI

enum FrontierAppearance: String, CaseIterable {
    case dark = "Dark", light = "Light", system = "System"
    static let key = "frontier.appearance"
    @MainActor static func apply(_ value: String) {
        switch FrontierAppearance(rawValue: value) ?? .dark {
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .system: NSApp.appearance = nil
        }
    }
}

struct LibrarySecondaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(LibraryTheme.ink)
            .background(LibraryTheme.chrome.opacity(configuration.isPressed ? 0.7 : 1), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LibraryTheme.rule, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
    }
}

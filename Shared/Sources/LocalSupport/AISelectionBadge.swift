import SwiftUI
import AppKit

public extension Notification.Name {
    static let localAISettingsChanged = Notification.Name("localAISettingsChanged")
}

/// Displays the same configuration used to send requests, refreshed after saving
/// settings and when returning from another app. A default is never a guessed model.
public struct AISelectionBadge: View {
    let load: () throws -> AISettings
    let configure: () -> Void
    let active: AISettings?
    @State private var settings: AISettings?
    @State private var error: String?
    public init(load: @escaping () throws -> AISettings, active: AISettings? = nil, configure: @escaping () -> Void) {
        self.load = load; self.active = active; self.configure = configure
    }
    public var body: some View {
        let selected = active ?? settings
        Button(action: configure) {
            HStack(spacing: 7) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected?.provider.title ?? "AI settings").font(.system(size: 11, weight: .medium))
                    Text(selected?.modelLabel ?? (error == nil ? "Loading…" : "Check settings"))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }.frame(maxWidth: 190, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(error ?? selected.map { $0.selectionLabel + ". " + ($0.model.isEmpty ? "The CLI chooses its default. Open AI settings to specify a model." : "Requested model. Open AI settings to change it.") } ?? "Open AI settings")
        .accessibilityLabel("AI settings: " + (selected?.selectionLabel ?? "Unavailable"))
        .accessibilityIdentifier("ai-selection")
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .localAISettingsChanged).receive(on: RunLoop.main)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() {
        do { settings = try load(); error = nil }
        catch { settings = nil; self.error = "Could not read AI settings: " + error.localizedDescription }
    }
}

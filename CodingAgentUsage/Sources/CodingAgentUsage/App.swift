import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep usage ready before the dropdown is first opened.
        MainActor.assumeIsolated { UsageStore.shared.start() }
    }
}

@main
struct CodingAgentUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: UsageStore

    init() {
        if CommandLine.arguments.contains("--selftest") {
            UsageSelfTest.run()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > index + 1 {
            UsageSelfTest.preview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        _store = State(initialValue: UsageStore.shared)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .accessibilityLabel("Coding Agent Usage")
                .help("Claude and Codex usage")
        }
        // .window is what makes it a panel anchored under the icon rather than a
        // dropdown menu or a free-floating window.
        .menuBarExtraStyle(.window)
    }
}

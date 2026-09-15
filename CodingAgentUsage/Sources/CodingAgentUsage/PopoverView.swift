import SwiftUI

struct PopoverView: View {
    @Bindable var store: UsageStore
    @Environment(\.colorScheme) private var scheme
    @State private var addingAccount = false
    @State private var accountName = ""
    @State private var provider = UsageProvider.claude
    @State private var renamingID: String?
    @State private var renameName = ""
    @State private var subscriptionID: String?
    @State private var subscriptionIdentity = ""
    @State private var subscriptionDay = Date()
    @State private var subscriptionKind = SubscriptionDateKind.renewal
    @State private var draggingID: String?
    @State private var dragLocation = CGPoint.zero
    @State private var accountFrames: [String: CGRect] = [:]

    init(store: UsageStore, showAddAccount: Bool = false, showSubscriptionEditor: Bool = false) {
        self.store = store
        _addingAccount = State(initialValue: showAddAccount)
        if showSubscriptionEditor, let entry = store.accounts.first, let identity = entry.state.snapshot.accountIdentity {
            _subscriptionID = State(initialValue: entry.id)
            _subscriptionIdentity = State(initialValue: identity)
            _subscriptionDay = State(initialValue: entry.savedSubscriptionDate?.date ?? Date())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.accounts) { entry in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    reorderTitle(entry)
                                    Menu {
                                        Button("Rename…") {
                                            renamingID = entry.id
                                            renameName = entry.account.name
                                        }
                                        Button(entry.savedSubscriptionDate == nil ? "Set subscription date…" : "Edit subscription date…") {
                                            editSubscription(entry)
                                        }.disabled(entry.state.snapshot.accountIdentity == nil)
                                        Divider()
                                        let index = store.accounts.firstIndex(where: { $0.id == entry.id }) ?? 0
                                        Button("Move to top") { store.moveAccount(entry.id, to: 0) }.disabled(index == 0)
                                        Button("Move up") { store.moveAccount(entry.id, to: index - 1) }.disabled(index == 0)
                                        Button("Move down") { store.moveAccount(entry.id, to: index + 1) }.disabled(index == store.accounts.count - 1)
                                        Button("Move to bottom") { store.moveAccount(entry.id, to: store.accounts.count - 1) }.disabled(index == store.accounts.count - 1)
                                        Divider()
                                        Button("Sign in…") { store.openAccount(entry.account, login: true) }
                                        Button("Open \(entry.account.provider.title)…") { store.openAccount(entry.account, login: false) }
                                        if !entry.account.followsCurrentLogin {
                                            Divider()
                                            Button("Remove from usage bar", role: .destructive) { store.removeAccount(entry.id) }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                    .help("Account options")
                                }
                                if renamingID == entry.id {
                                    TextField("Account name", text: $renameName).textFieldStyle(.roundedBorder)
                                    HStack {
                                        Button("Save name") {
                                            if store.renameAccount(entry.id, name: renameName) { renamingID = nil }
                                        }
                                        Button("Cancel") { renamingID = nil }
                                    }.font(.system(size: 11))
                                }
                                if let identity = entry.state.snapshot.identityLabel {
                                    Text(identity).font(.system(size: 10)).foregroundStyle(.secondary)
                                        .lineLimit(1).help(identity)
                                }
                                ProviderSection(title: "", snapshot: entry.state.snapshot, tick: store.tick)
                                subscriptionDetails(entry)
                                if let at = entry.state.snapshot.fetchedAt {
                                    Text("Updated \(at, style: .relative) ago")
                                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                                }
                            }
                            .id(entry.id)
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: AccountFrames.self,
                                    value: [entry.id: geometry.frame(in: .named("accountViewport"))])
                            })
                            .background(draggingID == entry.id ? Color.accentColor.opacity(0.08) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                            .overlay(alignment: .top) {
                                if insertionSlot == store.accounts.firstIndex(where: { $0.id == entry.id }) {
                                    insertionLine.offset(y: entry.id == store.accounts.first?.id ? 0 : -6)
                                }
                            }
                            Divider()
                        }
                        if insertionSlot == store.accounts.count { insertionLine }
                    }
                    // macOS overlay scrollbars occupy the scroll view's trailing edge.
                    // Reserve that space inside the content so values and menus stay clear.
                    .padding(.trailing, 20)
                }
                // MenuBarExtra can propose a compact size. A maximum alone lets the
                // scrollable account area collapse while the fixed footer stays visible.
                .frame(height: 430)
                .coordinateSpace(name: "accountViewport")
                .onPreferenceChange(AccountFrames.self) { accountFrames = $0 }
                .task(id: draggingID) {
                    guard draggingID != nil else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                        guard draggingID != nil else { return }
                        if let target = AccountReordering.scrollTarget(at: dragLocation.y, height: 430,
                            ids: store.accounts.map(\.id), frames: accountFrames) {
                            scrollProxy.scrollTo(target, anchor: dragLocation.y < 32 ? .top : .bottom)
                        }
                    }
                }
                .onDisappear { draggingID = nil }
                .background(GeometryReader { geometry in
                    Color.clear
                        .onAppear { store.recordAccountListHeight(geometry.size.height) }
                        .onChange(of: geometry.size.height) { _, height in store.recordAccountListHeight(height) }
                })
            }
            Divider().padding(.vertical, 8)
            accountControls
            Divider().padding(.top, 12).padding(.bottom, 8)
            footer
        }
        .padding(14)
        .frame(width: 340)
        .task {
            store.start()
            await store.refreshOnOpen()
        }
    }

    private var insertionSlot: Int? {
        guard draggingID != nil else { return nil }
        return AccountReordering.slot(at: dragLocation.y, ids: store.accounts.map(\.id), frames: accountFrames)
    }

    private var insertionLine: some View {
        Capsule().fill(Color.accentColor).frame(height: 2).allowsHitTesting(false)
    }

    private func reorderTitle(_ entry: AccountUsage) -> some View {
        Text("\(entry.account.provider.title) · \(entry.account.name)")
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("accountViewport"))
                .onChanged { value in
                    draggingID = entry.id
                    dragLocation = value.location
                }
                .onEnded { value in
                    defer { draggingID = nil }
                    // Releasing outside the list cancels rather than unexpectedly moving a row.
                    guard value.location.x >= 0, value.location.x <= 312,
                          value.location.y >= 0, value.location.y <= 430,
                          let source = store.accounts.firstIndex(where: { $0.id == entry.id }),
                          let slot = AccountReordering.slot(at: value.location.y,
                              ids: store.accounts.map(\.id), frames: accountFrames),
                          let destination = AccountReordering.destination(source: source, slot: slot, count: store.accounts.count) else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { _ = store.moveAccount(entry.id, to: destination) }
                })
            .help("Drag up or down; release at the blue line. Hold near an edge to scroll.")
            .accessibilityHint("Drag to reorder, or use the move commands in account options")
    }

    private func editSubscription(_ entry: AccountUsage) {
        guard let identity = entry.state.snapshot.accountIdentity else { return }
        subscriptionID = entry.id
        subscriptionIdentity = identity
        subscriptionDay = entry.savedSubscriptionDate?.date ?? entry.state.snapshot.subscriptionActiveUntil ?? Date()
        subscriptionKind = entry.savedSubscriptionDate?.kind ?? .renewal
    }

    @ViewBuilder private func subscriptionDetails(_ entry: AccountUsage) -> some View {
        if let saved = entry.savedSubscriptionDate, let date = saved.date {
            Text("\(saved.kind.title) \(date.formatted(date: .abbreviated, time: .omitted)) · saved")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        } else if let date = entry.state.snapshot.subscriptionActiveUntil {
            Text("Active through \(date.formatted(date: .abbreviated, time: .omitted)) · from login")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .help("Subscription information cached at sign-in. This may differ from the current billing renewal or cancellation date.")
        }
        if subscriptionID == entry.id {
            VStack(alignment: .leading, spacing: 7) {
                Picker("Subscription", selection: $subscriptionKind) {
                    ForEach(SubscriptionDateKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }.pickerStyle(.segmented)
                DatePicker("Date", selection: $subscriptionDay, displayedComponents: .date)
                    .datePickerStyle(.field)
                Text("Saved locally for this account. Update it when your plan changes.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                HStack {
                    Button("Save date") {
                        if store.saveSubscriptionDate(entry.id, identity: subscriptionIdentity,
                            date: SavedSubscriptionDate(date: subscriptionDay, kind: subscriptionKind)) { subscriptionID = nil }
                    }
                    if entry.savedSubscriptionDate != nil {
                        Button("Clear") {
                            if store.saveSubscriptionDate(entry.id, identity: subscriptionIdentity, date: nil) { subscriptionID = nil }
                        }
                    }
                    Button("Cancel") { subscriptionID = nil }
                }.font(.system(size: 11))
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var accountControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if addingAccount {
                Picker("Provider", selection: $provider) {
                    Text("Claude").tag(UsageProvider.claude)
                    Text("Codex").tag(UsageProvider.codex)
                }.pickerStyle(.segmented)
                TextField("Account name (e.g. Personal)", text: $accountName)
                    .textFieldStyle(.roundedBorder)
                Text("Sign in once for each account. Choose the matching account in your browser.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                HStack {
                    Button("Create & sign in") {
                        if let account = store.addAccount(name: accountName, provider: provider) {
                            addingAccount = false
                            accountName = ""
                            store.openAccount(account, login: true)
                        }
                    }
                    .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") { addingAccount = false }
                }
                Button("Use an existing \(provider.title) profile folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.showsHiddenFiles = true
                    panel.message = "Choose the folder you use as \(provider == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME") for this account."
                    if panel.runModal() == .OK, let url = panel.url,
                       store.addAccount(name: accountName, directory: url, provider: provider) != nil {
                        addingAccount = false
                        accountName = ""
                        Task { await store.refreshOnOpen() }
                    }
                }
                .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button { addingAccount = true } label: {
                    Label("Add account", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
            if let error = store.accountError {
                Text(error).font(.system(size: 10)).foregroundStyle(Severity.serious.color(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 11))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle("Open at login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            if let err = store.loginError {
                Text(err)
                    .font(.system(size: 9))
                    .foregroundStyle(Severity.serious.color(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Text(refreshedLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                Task { await store.manualRefresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help("Refresh now")

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var refreshedLabel: String {
        _ = store.tick
        guard let at = store.accounts.map({ $0.state.snapshot.fetchedAt })
            .compactMap({ $0 }).max() else {
            return store.isRefreshing ? "Refreshing…" : "Not yet loaded"
        }
        let s = Int(-at.timeIntervalSinceNow)
        if s < 60 { return "Updated just now" }
        return "Updated \(s / 60)m ago"
    }
}

private struct ProviderSection: View {
    let title: String
    let snapshot: ProviderSnapshot
    let tick: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !title.isEmpty || snapshot.plan != nil || snapshot.note != nil {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let plan = snapshot.plan {
                    Text(plan)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(.quaternary))
                }
                Spacer()
                if let note = snapshot.note {
                    Text(note).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            }

            if snapshot.meters.isEmpty {
                if let err = snapshot.error {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No limits reported").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            } else {
                ForEach(snapshot.meters) { MeterRow(meter: $0, tick: tick) }
                // Values stay on screen through a failed refresh; the badge says so.
                if snapshot.isStale, let err = snapshot.error {
                    Label(err, systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MeterRow: View {
    let meter: Meter
    let tick: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(meter.label)
                    .font(.system(size: 11))
                    .foregroundStyle(meter.isActive ? .primary : .secondary)
                    .lineLimit(1)
                if let reset = resetLabel {
                    Text(reset).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 6)
                if let sym = meter.severity.symbol {
                    Image(systemName: sym)
                        .font(.system(size: 9))
                        .foregroundStyle(meter.severity.color(scheme))
                }
                Text(Fmt.pct(meter.percent))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            bar
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(meter.severity.color(scheme))
                    .frame(width: max(meter.percent > 0 ? 3 : 0,
                                      geo.size.width * min(meter.percent, 100) / 100))
            }
        }
        .frame(height: 5)
    }

    private var resetLabel: String? {
        _ = tick
        guard let at = meter.resetsAt, let c = Fmt.countdown(to: at) else { return nil }
        return "· \(c)"
    }
}

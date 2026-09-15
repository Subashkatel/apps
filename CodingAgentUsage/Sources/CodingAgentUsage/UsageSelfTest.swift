import Foundation
import SwiftUI

private actor FetchGate {
    var pending: [String: CheckedContinuation<ProviderSnapshot, Never>] = [:]
    var calls = 0
    func fetch(_ account: UsageAccount) async -> ProviderSnapshot {
        calls += 1
        return await withCheckedContinuation { pending[account.id] = $0 }
    }
    func count() -> Int { calls }
    func release(_ snapshot: ProviderSnapshot) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(returning: snapshot) }
    }
}

enum UsageSelfTest {
    /// Synthetic local rendering only: no credentials or provider requests.
    @MainActor static func preview(to destination: URL) -> Never {
        Task { @MainActor in
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("usage-preview-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: scratch) }
            do {
                let store = UsageStore(settingsURL: scratch.appendingPathComponent("accounts.json"),
                                       fetchClaude: { _ in ProviderSnapshot() }, fetchCodex: { _ in ProviderSnapshot() })
                _ = store.addAccount(name: "Personal", directory: scratch.appendingPathComponent("personal"))
                _ = store.addAccount(name: "Work", directory: scratch.appendingPathComponent("work"))
                let now = Date()
                for i in store.accounts.indices {
                    var snapshot = ProviderSnapshot()
                    snapshot.meters = [
                        Meter(id: "session", label: "Session · 5h", percent: [24.0, 38, 83, 46][i], resetsAt: now.addingTimeInterval(7200), isActive: true),
                        Meter(id: "weekly", label: "Weekly · all models", percent: [57.0, 12, 61, 32][i], resetsAt: now.addingTimeInterval(172800), isActive: false)
                    ]
                    snapshot.fetchedAt = now
                    snapshot.accountIdentity = SubscriptionMetadata.identity(provider: store.accounts[i].account.provider, account: "synthetic-" + String(i))
                    if i == 1 { snapshot.subscriptionActiveUntil = now.addingTimeInterval(86400 * 15) }
                    store.accounts[i].state.apply(snapshot)
                    if i == 0, let identity = snapshot.accountIdentity {
                        store.accounts[i].account.subscriptionDates[identity] = SavedSubscriptionDate(date: now.addingTimeInterval(86400 * 20), kind: .renewal)
                    }
                }
                var codex = ProviderSnapshot()
                codex.error = "Sign in with Codex to view usage."
                // Codex is deliberately visible as the second account in the preview.
                _ = NSApplication.shared
                let adding = CommandLine.arguments.contains("--preview-add")
                let view = NSHostingView(rootView: PopoverView(store: store, showAddAccount: adding, showSubscriptionEditor: CommandLine.arguments.contains("--preview-date"))
                    .environment(\.colorScheme, .light).background(Color.white))
                let naturalSize = view.fittingSize
                print("Dropdown natural size: \(naturalSize.width) × \(naturalSize.height)")
                let height = CommandLine.arguments.contains("--preview-intrinsic") ? naturalSize.height : (adding ? 690 : 560)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view
                window.orderFront(nil)
                try await Task.sleep(for: .milliseconds(500))
                view.layoutSubtreeIfNeeded()
                if CommandLine.arguments.contains("--preview-drag") {
                    let firstID = store.accounts[0].id
                    // Dispatch events only to this synthetic window, never to another app.
                    @MainActor func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) {
                        if let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: height - y),
                            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                            window.sendEvent(event)
                        }
                    }
                    mouse(.leftMouseDown, x: 26, y: 26)
                    for y in stride(from: 32, through: 250, by: 8) {
                        mouse(.leftMouseDragged, x: 26, y: CGFloat(y))
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    mouse(.leftMouseUp, x: 26, y: 250)
                    try await Task.sleep(for: .milliseconds(300))
                    guard store.accounts[1].id == firstID else {
                        throw UsageError.message("Synthetic title drag did not move the first row below the second.")
                    }
                    print("PASS synthetic title drag moves the first account down one row")
                    let movedToBottom = store.accounts[0].id
                    mouse(.leftMouseDown, x: 26, y: 26)
                    for y in stride(from: 32, through: 430, by: 8) {
                        mouse(.leftMouseDragged, x: 26, y: CGFloat(y))
                        try await Task.sleep(for: .milliseconds(15))
                    }
                    try await Task.sleep(for: .milliseconds(1000))
                    mouse(.leftMouseUp, x: 26, y: 430)
                    try await Task.sleep(for: .milliseconds(300))
                    guard store.accounts.last?.id == movedToBottom else {
                        throw UsageError.message("Synthetic title drag did not scroll and insert at the bottom.")
                    }
                    let persisted = try UsageAccountsSettings.load(from: scratch.appendingPathComponent("accounts.json"))
                    guard persisted.accounts.map(\.id) == store.accounts.map(\.id) else {
                        throw UsageError.message("Drag order was not persisted.")
                    }
                    print("PASS synthetic title drag scrolls to bottom and saves order")
                }
                if CommandLine.arguments.contains("--preview-scrollbar") {
                    @MainActor func showScrollers(_ parent: NSView) {
                        if let scroll = parent as? NSScrollView {
                            scroll.scrollerStyle = .overlay
                            scroll.hasVerticalScroller = true
                            scroll.autohidesScrollers = false
                            scroll.flashScrollers()
                        }
                        for child in parent.subviews { showScrollers(child) }
                    }
                    showScrollers(view)
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
                try png.write(to: destination)
                window.orderOut(nil)
                print("Rendered synthetic usage preview.")
                exit(0)
            } catch { print("Preview failed: \(error)"); exit(1) }
        }
        RunLoop.main.run()
        fatalError("Preview run loop stopped unexpectedly")
    }

    @MainActor static func run() -> Never {
        Task { @MainActor in exit(await checks()) }
        RunLoop.main.run()
        fatalError("Self-test run loop stopped unexpectedly")
    }

    @MainActor private static func checks() async -> Int32 {
        var failures: Int32 = 0
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
        func rejects(_ action: () throws -> Void) -> Bool {
            do { try action(); return false } catch { return true }
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("usage-checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            let url = scratch.appendingPathComponent("accounts.json")
            let original = try UsageAccountsSettings.load(from: url)
            check("first launch preserves Current CLI", original.accounts == [.current, .currentCodex])
            let legacyURL = scratch.appendingPathComponent("legacy.json")
            let legacyJSON = #"{"version":1,"accounts":[{"id":"current-cli","name":"My Claude"}]}"#
            try Data(legacyJSON.utf8).write(to: legacyURL)
            let migrated = try UsageAccountsSettings.load(from: legacyURL)
            check("legacy accounts retain names and gain current Codex", migrated.accounts.map(\.provider) == [.claude, .codex]
                  && migrated.accounts[0].name == "My Claude")
            let v2URL = scratch.appendingPathComponent("v2.json")
            try Data(#"{"version":2,"accounts":[{"id":"current-codex","name":"Current CLI","provider":"codex"},{"id":"current-cli","name":"Custom Claude","provider":"claude"}]}"#.utf8).write(to: v2URL)
            let v2 = try UsageAccountsSettings.load(from: v2URL)
            check("v2 migration renames only default labels and preserves order", v2.accounts.map(\.name) == ["Local login", "Custom Claude"])
            let account = UsageAccount(id: UUID().uuidString, name: "Personal", configDirectory: "/tmp/claude-account-a")
            check("default CLI uses the legacy service", UsageAccount.current.keychainService == "Claude Code-credentials")
            check("profiles have isolated Keychain services", account.keychainService != UsageAccount.current.keychainService)
            check("profile service matches Claude Code's SHA256 convention", account.keychainService == "Claude Code-credentials-5437a5d6")
            let other = UsageAccount(id: UUID().uuidString, name: "Work", configDirectory: "/tmp/claude-account-b")
            check("different profiles never share a service", other.keychainService != account.keychainService)
            check("empty name rejected", rejects { _ = try UsageAccount.validatedName(" \n") })
            check("relative profile folder rejected", rejects { _ = try UsageAccount.normalizedDirectory("relative/path") })
            check("control characters in labels rejected", rejects { _ = try UsageAccount.validatedName("one\ntwo") })
            let settings = UsageAccountsSettings(accounts: [.current, .currentCodex, account])
            try settings.save(to: url)
            let loaded = try UsageAccountsSettings.load(from: url)
            check("profiles survive restart", loaded.accounts == settings.accounts)
            let json = try String(contentsOf: url)
            check("settings contain no tokens", !json.contains("accessToken") && !json.contains("refreshToken"))
            check("duplicate profile folders rejected", rejects {
                var duplicate = account
                duplicate.id = UUID().uuidString
                _ = try UsageAccountsSettings(accounts: [.current, .currentCodex, account, duplicate]).validated()
            })
            let future = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
            let data = try JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": "synthetic-token-a", "expiresAt": future]])
            let credential = try ClaudeClient.credential(from: data)
            check("valid credential parsed without expiration", credential.token == "synthetic-token-a" && !credential.expired)
            let expiredData = Data(#"{"claudeAiOauth":{"accessToken":"synthetic-token-b","expiresAt":1}}"#.utf8)
            let expired = try ClaudeClient.credential(from: expiredData)
            check("expired login detected before polling", expired.expired)
            check("different credentials have different markers", expired.fingerprint != credential.fingerprint)
            check("empty credentials rejected", rejects { _ = try ClaudeClient.credential(from: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) })
            let claims = Data(#"{"email":"synthetic@example.invalid"}"#.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            let codexData = try JSONSerialization.data(withJSONObject: ["tokens": ["access_token": "synthetic-codex",
                "account_id": "synthetic-account", "id_token": "header." + claims + ".signature"]])
            let codexCredentials = try CodexClient.credentials(from: codexData)
            check("Codex login identity and account routing are parsed separately", codexCredentials.accountID == "synthetic-account"
                  && codexCredentials.email == "synthetic@example.invalid" && codexCredentials.token == "synthetic-codex")
            check("API-only Codex credentials do not masquerade as subscription usage", rejects {
                _ = try CodexClient.credentials(from: Data(#"{"OPENAI_API_KEY":"synthetic-api-key"}"#.utf8))
            })

            check("JWT expiry does not stand in for subscription expiry", codexCredentials.subscriptionEnd == nil)
            let subscriptionClaims = Data(#"{"exp":1,"https://api.openai.com/auth":{"chatgpt_subscription_active_until":"2026-10-20T12:00:00Z"}}"#.utf8).base64EncodedString()
            let subscriptionAuth = try JSONSerialization.data(withJSONObject: ["tokens": ["access_token": "synthetic", "id_token": "a." + subscriptionClaims + ".b"]])
            let parsedSubscription = try CodexClient.credentials(from: subscriptionAuth)
            check("explicit Codex subscription date parsed independently of token expiry", parsedSubscription.subscriptionEnd == SubscriptionMetadata.activeUntil("2026-10-20T12:00:00Z"))
            check("unavailable or malformed subscription dates stay unknown", SubscriptionMetadata.activeUntil(NSNull()) == nil && SubscriptionMetadata.activeUntil("nonsense") == nil)
            let identityA = SubscriptionMetadata.identity(provider: .claude, account: "account-a", organization: "org")!
            let identityB = SubscriptionMetadata.identity(provider: .claude, account: "account-b", organization: "org")!
            check("stable identity separates accounts and providers", identityA != identityB && identityA != SubscriptionMetadata.identity(provider: .codex, account: "account-a", organization: "org"))
            let savedDate = SavedSubscriptionDate(date: SubscriptionMetadata.activeUntil("2026-10-20T12:00:00Z")!, kind: .renewal)
            check("manual date round trips as a calendar day", try JSONDecoder().decode(SavedSubscriptionDate.self, from: JSONEncoder().encode(savedDate)) == savedDate && savedDate.date != nil)
            var invalidDate = savedDate
            invalidDate.day = "2026-02-30"
            check("impossible calendar dates rejected", invalidDate.date == nil)

            var good = ProviderSnapshot()
            good.meters = [Meter(id: "five_hour", label: "Session", percent: 72, resetsAt: nil, isActive: true)]
            good.fetchedAt = Date()
            good.credentialFingerprint = "account-a"
            good.accountIdentity = identityA
            var stateA = UsagePollingState(), stateB = UsagePollingState()
            let now = Date()
            stateA.apply(good, now: now)
            stateB.apply(good, now: now)
            var error = ProviderSnapshot()
            error.error = "Rate limited"
            error.retryAfter = 420
            error.credentialFingerprint = "account-a"
            stateA.apply(error, now: now)
            check("transient failure preserves same-login usage", stateA.snapshot.headline?.percent == 72 && stateA.snapshot.isStale)
            check("rate-limit backoff is per account", stateA.next == now.addingTimeInterval(420) && stateB.failures == 0)
            stateA.refreshOnOpen(now: now.addingTimeInterval(100))
            check("opening panel respects active backoff", stateA.next == now.addingTimeInterval(420))
            error.credentialFingerprint = "account-b"
            stateA.apply(error, now: now)
            check("login changes discard previous account numbers", stateA.snapshot.meters.isEmpty)
            stateA.apply(good, now: now)
            check("successful refresh clears stale error", stateA.failures == 0 && !stateA.snapshot.isStale && stateA.snapshot.error == nil)
            error.retryAfter = 99_999
            stateA.apply(error, now: now)
            check("backoff is bounded", stateA.next == now.addingTimeInterval(1800))

            let trickyPath = scratch.appendingPathComponent("profile ' $(touch SHOULD_NOT_EXIST)").path
            let tricky = UsageAccount(id: UUID().uuidString, name: "Quoted", configDirectory: trickyPath)
            let command = UsageLauncher.command(account: tricky, executable: URL(fileURLWithPath: "/usr/bin/printenv"), login: false)
                + " CLAUDE_CONFIG_DIR"
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = scratch
            process.standardOutput = output
            try process.run()
            let emitted = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            check("launcher treats shell syntax as literal profile path", String(data: emitted, encoding: .utf8) == trickyPath + "\n"
                  && !FileManager.default.fileExists(atPath: scratch.appendingPathComponent("SHOULD_NOT_EXIST").path))

            let gate = FetchGate()
            let store = UsageStore(settingsURL: url, fetchClaude: { await gate.fetch($0) }, fetchCodex: { _ in ProviderSnapshot() })
            let poll = Task { await store.pollDue() }
            for _ in 0..<100 {
                if await gate.count() == 2 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            await store.pollDue()
            check("overlapping refresh does not duplicate account requests", await gate.count() == 2)
            store.removeAccount(account.id)
            await gate.release(good)
            await poll.value
            check("removed in-flight account stays removed", store.accounts.map(\.id) == [UsageAccount.current.id, UsageAccount.currentCodex.id])
            let added = store.addAccount(name: "Work", directory: scratch.appendingPathComponent("work"))
            check("account can be added without accessing credentials", added != nil && store.accounts.count == 3)
            check("duplicate names are rejected", store.addAccount(name: "work", directory: scratch.appendingPathComponent("other")) == nil)
            check("duplicate profile rejected", store.addAccount(name: "Another", directory: scratch.appendingPathComponent("work")) == nil)
            check("current Claude can be renamed", store.renameAccount(UsageAccount.current.id, name: "My Claude"))
            check("current Codex can be renamed", store.renameAccount(UsageAccount.currentCodex.id, name: "My Codex"))
            let renamed = try UsageAccountsSettings.load(from: url)
            check("renaming preserves automatic current-login detection", renamed.accounts.prefix(2).allSatisfy { $0.configDirectory == nil }
                  && renamed.accounts[0].name == "My Claude" && renamed.accounts[1].name == "My Codex")
            store.removeAccount(UsageAccount.currentCodex.id)
            check("current Codex cannot be accidentally removed", store.accounts.contains { $0.id == UsageAccount.currentCodex.id })
            let extraCodex = store.addAccount(name: "Work", directory: scratch.appendingPathComponent("codex-work"), provider: .codex)
            check("additional Codex profiles can share a label with Claude", extraCodex?.provider == .codex)
            if let extraCodex {
                let command = UsageLauncher.command(account: extraCodex, executable: URL(fileURLWithPath: "/tmp/codex"), login: true)
                check("Codex login uses isolated home and consistent credential storage", command.contains("CODEX_HOME=" + UsageLauncher.quote(extraCodex.directory.path))
                      && command.contains("cli_auth_credentials_store=") && command.hasSuffix(" login"))
            }
            let rowIDs = ["a", "b", "c"]
            let frames: [String: CGRect] = ["a": CGRect(x: 0, y: 0, width: 300, height: 100),
                "b": CGRect(x: 0, y: 112, width: 300, height: 160),
                "c": CGRect(x: 0, y: 284, width: 300, height: 180)]
            check("lower half of adjacent row inserts after it", AccountReordering.slot(at: 230, ids: rowIDs, frames: frames) == 2
                  && AccountReordering.destination(source: 0, slot: 2, count: 3) == 1)
            check("drag can insert at the very bottom", AccountReordering.slot(at: 420, ids: rowIDs, frames: frames) == 3
                  && AccountReordering.destination(source: 0, slot: 3, count: 3) == 2)
            check("drag can insert above the first row", AccountReordering.slot(at: 10, ids: rowIDs, frames: frames) == 0
                  && AccountReordering.destination(source: 2, slot: 0, count: 3) == 0)
            check("dropping within original slot keeps order", AccountReordering.destination(source: 1, slot: 2, count: 3) == 1)
            check("unmeasured rows do not yield an invented drop target", AccountReordering.slot(at: 20, ids: rowIDs, frames: [:]) == nil)
            check("holding at bottom scrolls to clipped row", AccountReordering.scrollTarget(at: 420, height: 430, ids: rowIDs, frames: frames) == "c")
            let shifted = frames.mapValues { $0.offsetBy(dx: 0, dy: -150) }
            check("scroll coordinates change insertion target", AccountReordering.slot(at: 230, ids: rowIDs, frames: shifted) == 3)
            check("holding at top scrolls to preceding row", AccountReordering.scrollTarget(at: 10, height: 430, ids: rowIDs, frames: shifted) == "b")
            let currentID = UsageAccount.current.id
            let codexID = UsageAccount.currentCodex.id
            check("local login can move to bottom", store.moveAccount(currentID, to: store.accounts.count - 1) && store.accounts.last?.id == currentID)
            check("reordering keeps usage with its account", store.accounts.last?.state.snapshot.headline?.percent == 72)
            check("order survives restart", try UsageAccountsSettings.load(from: url).accounts.map(\.id) == store.accounts.map(\.id))
            check("drag moves an account above its target", store.moveAccount(currentID, before: codexID) && store.accounts.first?.id == currentID)
            check("invalid reorder is ignored", !store.moveAccount("missing", to: 0) && !store.moveAccount(currentID, to: -1))
            check("subscription date can be saved", store.saveSubscriptionDate(currentID, identity: identityA, date: savedDate))
            let restarted = UsageStore(settingsURL: url, fetchClaude: { _ in ProviderSnapshot() }, fetchCodex: { _ in ProviderSnapshot() })
            check("saved date survives restart", restarted.accounts.first?.account.subscriptionDates[identityA] == savedDate)
            store.accounts[0].state.snapshot.accountIdentity = identityB
            check("switching login hides other account's date", store.accounts[0].savedSubscriptionDate == nil)
            check("login switch while editing prevents a wrong-account save", !store.saveSubscriptionDate(currentID, identity: identityA, date: savedDate))
            store.accounts[0].state.snapshot.accountIdentity = identityA
            store.accounts[0].state.snapshot.credentialFingerprint = "rotated-token"
            check("returning login and token rotation retain saved date", store.accounts[0].savedSubscriptionDate == savedDate)
            check("date can be cleared", store.saveSubscriptionDate(currentID, identity: identityA, date: nil) && store.accounts[0].savedSubscriptionDate == nil)
            check("cleared date stays cleared after restart", try UsageAccountsSettings.load(from: url).accounts[0].subscriptionDates.isEmpty)
            let brokenURL = scratch.appendingPathComponent("broken.json")
            try Data("{broken".utf8).write(to: brokenURL)
            let broken = UsageStore(settingsURL: brokenURL, fetchClaude: { _ in ProviderSnapshot() }, fetchCodex: { _ in ProviderSnapshot() })
            check("malformed settings report a recoverable error", broken.accountError != nil)
            let refused = broken.addAccount(name: "Ignored") == nil
            let unchanged = try String(contentsOf: brokenURL)
            check("malformed settings are not overwritten", refused && unchanged == "{broken")
        } catch {
            check("unexpected test error: \(error)", false)
        }
        print("Coding Agent Usage checks finished: \(failures) failures")
        return failures == 0 ? 0 : 1
    }
}

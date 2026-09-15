import SwiftUI
import Observation
import LocalSupport

@MainActor
@Observable
final class UsageStore {
    static let shared = UsageStore()

    var accounts: [AccountUsage]
    var isRefreshing = false
    var tick = 0
    var launchAtLogin = LoginItem.isEnabled
    var loginError: String?
    var accountError: String?
    private var canSave = true
    private var pollTask: Task<Void, Never>?
    private var lastManual = Date.distantPast
    private let settingsURL: URL
    @ObservationIgnored private var accountListHeight: CGFloat?
    @ObservationIgnored private let fetchClaude: (UsageAccount) async -> ProviderSnapshot
    @ObservationIgnored private let fetchCodex: (UsageAccount) async -> ProviderSnapshot

    init(settingsURL: URL = UsageAccountsSettings.fileURL,
         fetchClaude: @escaping (UsageAccount) async -> ProviderSnapshot = { await ClaudeClient.fetch(account: $0) },
         fetchCodex: @escaping (UsageAccount) async -> ProviderSnapshot = { await CodexClient.fetch(account: $0) }) {
        self.settingsURL = settingsURL
        self.fetchClaude = fetchClaude
        self.fetchCodex = fetchCodex
        do {
            let settings = try UsageAccountsSettings.load(from: settingsURL)
            accounts = settings.accounts.map { AccountUsage(account: $0) }
        } catch {
            accounts = [AccountUsage(account: .current), AccountUsage(account: .currentCodex)]
            accountError = "Could not read account settings. Restore claude-accounts.json before editing accounts."
            canSave = false
        }
        writeStatus()
    }

    func recordAccountListHeight(_ height: CGFloat) {
        guard accountListHeight != height else { return }
        accountListHeight = height
        writeStatus()
    }

    /// Local health information only: no emails, tokens, or account usage values.
    private func writeStatus() {
        var report: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "accounts": accounts.map { entry -> [String: Any] in
                var row: [String: Any] = ["provider": entry.account.provider.rawValue,
                                         "followsCurrentLogin": entry.account.followsCurrentLogin,
                                         "usageWindows": entry.state.snapshot.meters.count,
                                         "identityDetected": entry.state.snapshot.identityLabel != nil]
                if let error = entry.state.snapshot.error { row["error"] = error }
                return row
            }
        ]
        if let accountListHeight { report["accountListHeight"] = accountListHeight }
        let url = settingsURL.deletingLastPathComponent().appendingPathComponent("runtime.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        } catch { /* Diagnostic failures must not disrupt usage polling. */ }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollDue()
                try? await Task.sleep(for: .seconds(15))
                self?.tick += 1
            }
        }
    }

    func refreshOnOpen() async {
        for i in accounts.indices { accounts[i].state.refreshOnOpen() }
        await pollDue()
    }

    func manualRefresh() async {
        guard !isRefreshing, Date().timeIntervalSince(lastManual) > 15 else { return }
        lastManual = Date()
        for i in accounts.indices { accounts[i].state.next = .distantPast }
        await pollDue()
    }

    func pollDue() async {
        guard !isRefreshing else { return }
        let now = Date()
        let accounts = accounts.filter { now >= $0.state.next }.map(\.account)
        guard !accounts.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false; writeStatus() }
        await withTaskGroup(of: (String, ProviderSnapshot).self) { group in
            for account in accounts {
                group.addTask { [fetchClaude, fetchCodex] in
                    let snapshot = account.provider == .claude ? await fetchClaude(account) : await fetchCodex(account)
                    return (account.id, snapshot)
                }
            }
            for await (id, snapshot) in group {
                // A completed request may not resurrect a removed profile.
                if let index = self.accounts.firstIndex(where: { $0.id == id }) {
                    self.accounts[index].state.apply(snapshot)
                    writeStatus()
                }
            }
        }
    }

    @discardableResult
    func addAccount(name: String, directory: URL? = nil, provider: UsageProvider = .claude) -> UsageAccount? {
        do {
            let id = UUID().uuidString
            let path = try UsageAccount.normalizedDirectory(directory?.path
                ?? LocalConfig.dataDirectory("CodingAgentUsage").appendingPathComponent(provider.title + "Profiles/" + id).path)
            // The default directory is already represented by Current CLI. Explicitly setting
            // CLAUDE_CONFIG_DIR to ~/.claude can select a different Keychain item; avoid that trap.
            let current = provider == .claude ? UsageAccount.current : .currentCodex
            guard path != current.directory.standardizedFileURL.path,
                  !accounts.contains(where: { $0.account.provider == provider && $0.account.configDirectory == path }) else {
                throw UsageError.message("That profile is already listed.")
            }
            let account = UsageAccount(id: id, name: try UsageAccount.validatedName(name), configDirectory: path, provider: provider)
            guard !accounts.contains(where: { $0.account.provider == provider && $0.account.name.localizedCaseInsensitiveCompare(account.name) == .orderedSame }) else {
                throw UsageError.message("Choose a different name for this account.")
            }
            let updated = accounts + [AccountUsage(account: account)]
            try persist(updated)
            accounts = updated
            accountError = nil
            return account
        } catch { showAccountError(error); return nil }
    }

    func removeAccount(_ id: String) {
        guard id != UsageAccount.current.id, id != UsageAccount.currentCodex.id else { return }
        let updated = accounts.filter { $0.id != id }
        do {
            try persist(updated)
            accounts = updated
            accountError = nil
        } catch { showAccountError(error) }
    }

    private func persist(_ accounts: [AccountUsage]) throws {
        guard canSave else { throw UsageError.message("Restore claude-accounts.json before editing accounts.") }
        try UsageAccountsSettings(accounts: accounts.map(\.account)).save(to: settingsURL)
    }

    @discardableResult
    func moveAccount(_ id: String, to destination: Int) -> Bool {
        guard let source = accounts.firstIndex(where: { $0.id == id }),
              accounts.indices.contains(destination) else { return false }
        if source == destination { return true }
        var updated = accounts
        updated.insert(updated.remove(at: source), at: destination)
        do {
            try persist(updated)
            accounts = updated
            accountError = nil
            return true
        } catch { showAccountError(error); return false }
    }

    @discardableResult
    func moveAccount(_ id: String, before target: String) -> Bool {
        guard let source = accounts.firstIndex(where: { $0.id == id }),
              let destination = accounts.firstIndex(where: { $0.id == target }) else { return false }
        if source == destination { return true }
        return moveAccount(id, to: destination - (source < destination ? 1 : 0))
    }

    @discardableResult
    func saveSubscriptionDate(_ id: String, identity: String, date: SavedSubscriptionDate?) -> Bool {
        do {
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return false }
            guard accounts[index].state.snapshot.accountIdentity == identity else {
                throw UsageError.message("The login changed. Reopen the subscription date editor for this account.")
            }
            var updated = accounts
            updated[index].account.subscriptionDates[identity] = date
            try persist(updated)
            accounts = updated
            accountError = nil
            return true
        } catch { showAccountError(error); return false }
    }

    @discardableResult
    func renameAccount(_ id: String, name: String) -> Bool {
        do {
            let label = try UsageAccount.validatedName(name)
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return false }
            let provider = accounts[index].account.provider
            guard !accounts.contains(where: { $0.id != id && $0.account.provider == provider && $0.account.name.localizedCaseInsensitiveCompare(label) == .orderedSame }) else {
                throw UsageError.message("Choose a different name for this account.")
            }
            var updated = accounts
            updated[index].account.name = label
            try persist(updated)
            accounts = updated
            accountError = nil
            return true
        } catch { showAccountError(error); return false }
    }

    func openAccount(_ account: UsageAccount, login: Bool) {
        do {
            try UsageLauncher.open(account, login: login)
            accountError = nil
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index].state.next = Date().addingTimeInterval(15)
            }
        } catch { showAccountError(error) }
    }

    private func showAccountError(_ error: Error) {
        accountError = (error as? UsageError)?.text ?? error.localizedDescription
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            loginError = nil
        } catch {
            loginError = LoginItem.isBlockedByUser
                ? "Allow it in System Settings › General › Login Items." : error.localizedDescription
        }
        launchAtLogin = LoginItem.isEnabled
    }

}

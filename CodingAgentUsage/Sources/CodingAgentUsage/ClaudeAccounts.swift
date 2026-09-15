import AppKit
import CryptoKit
import Foundation
import LocalSupport

/// Local account preferences contain no tokens.
enum UsageProvider: String, Codable, CaseIterable {
    case claude, codex
    var title: String { rawValue.capitalized }
}

struct UsageAccount: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// nil follows the provider’s ordinary local CLI login.
    var configDirectory: String?
    var provider: UsageProvider = .claude
    var subscriptionDates: [String: SavedSubscriptionDate] = [:]

    static let current = UsageAccount(id: "current-cli", name: "Local login", configDirectory: nil)

    static let currentCodex = UsageAccount(id: "current-codex", name: "Local login", configDirectory: nil, provider: .codex)

    var followsCurrentLogin: Bool { configDirectory == nil }

    enum CodingKeys: String, CodingKey { case id, name, configDirectory, provider, subscriptionDates }
    init(id: String, name: String, configDirectory: String?, provider: UsageProvider = .claude) {
        self.id = id; self.name = name; self.configDirectory = configDirectory; self.provider = provider
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        configDirectory = try c.decodeIfPresent(String.self, forKey: .configDirectory)
        provider = try c.decodeIfPresent(UsageProvider.self, forKey: .provider) ?? .claude
        subscriptionDates = try c.decodeIfPresent([String: SavedSubscriptionDate].self, forKey: .subscriptionDates) ?? [:]
    }

    var directory: URL {
        if let configDirectory { return URL(fileURLWithPath: configDirectory) }
        if provider == .codex { return CodexClient.authPath.deletingLastPathComponent() }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    var keychainService: String {
        guard let configDirectory else { return "Claude Code-credentials" }
        // Matches the installed Claude Code 2.1.270 credential service naming.
        let normalized = configDirectory.precomposedStringWithCanonicalMapping
        let hash = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-" + hash.prefix(8)
    }

    static func validatedName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40,
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw UsageError.message("Use an account name of 1–40 characters.")
        }
        return name
    }

    static func normalizedDirectory(_ raw: String) throws -> String {
        let expanded = (raw as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), !expanded.contains("\0") else {
            throw UsageError.message("Choose an absolute profile folder.")
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path.precomposedStringWithCanonicalMapping
    }
}

struct UsageAccountsSettings: Codable {
    var version = 3
    var accounts: [UsageAccount] = [.current, .currentCodex]

    init(accounts: [UsageAccount] = [.current, .currentCodex]) { self.accounts = accounts }
    enum CodingKeys: String, CodingKey { case version, accounts }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try c.decode(Int.self, forKey: .version)
        guard [1, 2, 3].contains(storedVersion) else { throw UsageError.message("Unsupported account settings version.") }
        accounts = try c.decode([UsageAccount].self, forKey: .accounts)
        if storedVersion == 1, !accounts.contains(where: { $0.id == UsageAccount.currentCodex.id }) {
            accounts.insert(.currentCodex, at: min(1, accounts.count))
        }
        if storedVersion < 3 {
            for i in accounts.indices where accounts[i].followsCurrentLogin && accounts[i].name == "Current CLI" {
                // Preserve custom names, including a deliberate rename back after migration.
                if !accounts.contains(where: { $0.provider == accounts[i].provider && $0.name == "Local login" }) {
                    accounts[i].name = "Local login"
                }
            }
        }
    }

    func validated() throws -> Self {
        guard !accounts.isEmpty, Set(accounts.map(\.id)).count == accounts.count else {
            throw UsageError.message("Invalid account settings. Restore claude-accounts.json before editing accounts.")
        }
        var directories = Set<String>()
        for account in accounts {
            let defaultID = account.provider == .claude ? UsageAccount.current.id : UsageAccount.currentCodex.id
            guard account.id == defaultID || UUID(uuidString: account.id) != nil else {
                throw UsageError.message("Invalid account identifier.")
            }
            _ = try UsageAccount.validatedName(account.name)
            for (identity, saved) in account.subscriptionDates {
                guard identity.count == 64, identity.allSatisfy({ $0.isHexDigit }), saved.date != nil else {
                    throw UsageError.message("Invalid saved subscription date.")
                }
            }
            if let directory = account.configDirectory {
                guard account.id != defaultID, try UsageAccount.normalizedDirectory(directory) == directory,
                      directories.insert(account.provider.rawValue + ":" + directory).inserted else {
                    throw UsageError.message("Duplicate or invalid profile folder.")
                }
            } else if account.id != defaultID {
                throw UsageError.message("Only the current-login entries can use default credentials.")
            }
        }
        for current in [UsageAccount.current, .currentCodex] {
            guard accounts.contains(where: { $0.id == current.id && $0.provider == current.provider && $0.configDirectory == nil }) else {
                throw UsageError.message("A current-login account is missing.")
            }
        }
        return self
    }

    // Preserve the original filename so existing account setups migrate in place.
    static var fileURL: URL {
        LocalConfig.dataDirectory("CodingAgentUsage").appendingPathComponent("claude-accounts.json")
    }
    static func load(from url: URL = fileURL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)).validated()
    }
    func save(to url: URL = fileURL) throws {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

enum UsageLauncher {
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// No credentials in the generated script. Environment overrides cannot redirect a login.
    static func command(account: UsageAccount, executable: URL, login: Bool) -> String {
        if account.provider == .codex {
            let unset = ["OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "CODEX_HOME", "CODEX_AUTH_FILE"]
                .map { "-u " + $0 }.joined(separator: " ")
            // Named profiles use CLI-managed file storage consistently for login and use.
            let profile = " CODEX_HOME=" + quote(account.directory.path)
            return "/usr/bin/env " + unset + profile + " " + quote(executable.path)
                + " -c " + quote("cli_auth_credentials_store=\"file\"") + (login ? " login" : "")
        }
        let unset = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
                     "CLAUDE_CONFIG_DIR", "CLAUDE_SECURESTORAGE_CONFIG_DIR", "ANTHROPIC_BASE_URL",
                     "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"]
            .map { "-u " + $0 }.joined(separator: " ")
        let profile = account.configDirectory.map { " CLAUDE_CONFIG_DIR=" + quote($0) } ?? ""
        return "/usr/bin/env " + unset + profile + " " + quote(executable.path)
            + (login ? " auth login --claudeai" : "")
    }

    @MainActor
    static func open(_ account: UsageAccount, login: Bool) throws {
        let provider = account.provider
        guard let executable = LocalConfig.executable(provider.rawValue + "Path",
                environment: "LOCAL_APPS_" + provider.rawValue.uppercased(), name: provider.rawValue) else {
            throw UsageError.message("\(provider.title) CLI was not found. Configure its path in the local apps settings.")
        }
        if account.configDirectory != nil {
            try FileManager.default.createDirectory(at: account.directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let scripts = LocalConfig.dataDirectory("CodingAgentUsage").appendingPathComponent("Launchers")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = scripts.appendingPathComponent(account.id + (login ? "-login.command" : "-open.command"))
        let script = "#!/bin/bash\ncd \"$HOME\" || exit 1\n" + command(account: account, executable: executable, login: login)
            + "\nresult=$?\nprintf '\\nFinished (exit %s). You can close this window.\\n' \"$result\"\nexit \"$result\"\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        // .command files run visibly in Terminal; the user completes the provider's login.
        guard NSWorkspace.shared.open(url) else { throw UsageError.message("Could not open Terminal for this account.") }
    }
}

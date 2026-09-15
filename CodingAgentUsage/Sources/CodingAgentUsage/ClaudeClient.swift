import Foundation
import CryptoKit

/// Reads the same OAuth credential Claude Code stores in the login keychain and
/// calls the endpoint that backs `/usage`.
enum ClaudeClient {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Shell out to /usr/bin/security rather than SecItemCopyMatching: the keychain
    /// ACL is keyed to the requesting binary, and `security` is a stable system path,
    /// so the one-time "Always Allow" survives every rebuild of this app.
    static func credential(from data: Data) throws -> (token: String, fingerprint: String, expired: Bool) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw UsageError.message("No Claude subscription login found. Use Sign in for this account.")
        }
        let fingerprint = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        let expired = (oauth["expiresAt"] as? Double).map { $0 / 1000 <= Date().timeIntervalSince1970 } ?? false
        return (token, fingerprint, expired)
    }

    static func accessToken(for account: UsageAccount) throws -> (token: String, fingerprint: String, expired: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        let user = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        let keychainUser = user.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil ? user : "claude-code-user"
        p.arguments = ["find-generic-password", "-s", account.keychainService, "-a", keychainUser, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        if p.terminationStatus == 0, !data.isEmpty {
            return try credential(from: data)
        }
        // Claude's documented fallback belongs to this exact profile, never another account.
        let fallback = account.directory.appendingPathComponent(".credentials.json")
        if let data = try? Data(contentsOf: fallback) {
            return try credential(from: data)
        }
        throw UsageError.message("Sign in to this account, or allow its Claude Keychain item when prompted.")
    }

    static func fetch(account: UsageAccount = .current) async -> ProviderSnapshot {
        var snap = ProviderSnapshot()
        do {
            let credential = try accessToken(for: account)
            snap.credentialFingerprint = credential.fingerprint
            let metadataURL = account.configDirectory == nil
                ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
                : account.directory.appendingPathComponent(".claude.json")
            if let data = try? Data(contentsOf: metadataURL),
               let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let identity = metadata["oauthAccount"] as? [String: Any] {
                snap.identityLabel = identity["emailAddress"] as? String
                snap.accountIdentity = SubscriptionMetadata.identity(provider: .claude,
                    account: identity["accountUuid"] as? String ?? snap.identityLabel,
                    organization: identity["organizationUuid"] as? String)
            }
            if credential.expired {
                throw UsageError.message("Login expired. Open Claude for this account to refresh, or use Sign in.")
            }
            var req = URLRequest(url: usageURL)
            req.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.timeoutInterval = 15

            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            if code == 401 || code == 403 {
                throw UsageError.message("Login needs attention. Open Claude for this account, or use Sign in.")
            }
            if code == 429 {
                snap.retryAfter = HTTPHint.retryAfter(http)
                throw UsageError.message("Rate limited — backing off.")
            }
            guard code == 200 else { throw UsageError.message("HTTP \(code)") }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw UsageError.message("Bad response.")
            }

            snap.meters = parseMeters(json)
            snap.fetchedAt = Date()

            if let extra = json["extra_usage"] as? [String: Any],
               extra["is_enabled"] as? Bool == true,
               let util = extra["utilization"] as? Double {
                snap.note = "Extra usage \(Fmt.pct(util))"
            }
        } catch let e as UsageError {
            snap.error = e.text
        } catch {
            snap.error = error.localizedDescription
        }
        return snap
    }

    /// `limits[]` is the general form — it carries per-model weekly windows that the
    /// flat five_hour/seven_day fields don't. Fall back to the flat fields if absent.
    private static func parseMeters(_ json: [String: Any]) -> [Meter] {
        if let limits = json["limits"] as? [[String: Any]], !limits.isEmpty {
            return limits.compactMap { l in
                guard let pct = l["percent"] as? Double else { return nil }
                let kind = l["kind"] as? String ?? "limit"
                var label: String
                switch kind {
                case "session": label = "Session · 5h"
                case "weekly_all": label = "Weekly · all models"
                case "weekly_scoped":
                    let model = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                    label = "Weekly · \(model ?? "scoped")"
                default: label = kind.replacingOccurrences(of: "_", with: " ").capitalized
                }
                return Meter(
                    id: "claude.\(kind).\(label)",
                    label: label,
                    percent: pct,
                    resetsAt: date(l["resets_at"]),
                    isActive: l["is_active"] as? Bool ?? false
                )
            }
        }

        var out: [Meter] = []
        for (key, label) in [("five_hour", "Session · 5h"), ("seven_day", "Weekly · all models")] {
            if let w = json[key] as? [String: Any], let pct = w["utilization"] as? Double {
                out.append(Meter(id: "claude.\(key)", label: label, percent: pct,
                                 resetsAt: date(w["resets_at"]), isActive: key == "five_hour"))
            }
        }
        return out
    }

    private static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

struct UsageError: Error {
    let text: String
    static func message(_ s: String) -> UsageError { UsageError(text: s) }
}

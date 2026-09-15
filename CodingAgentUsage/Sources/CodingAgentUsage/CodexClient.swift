import LocalSupport
import Foundation
import CryptoKit

/// Reads ~/.codex/auth.json — the credential the Codex CLI maintains — and calls the
/// endpoint that backs the usage view.
enum CodexClient {
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static var authPath: URL {
        if let path = LocalConfig.path("codexAuthFile", environment: "CODEX_AUTH_FILE") { return path }
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return home.appendingPathComponent("auth.json")
    }

    static func credentials(from data: Data) throws -> (token: String, accountID: String, email: String?, subscriptionEnd: Date?) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let token = tokens["access_token"] as? String, !token.isEmpty
        else {
            throw UsageError.message("Unexpected credential format.")
        }
        // Decode display metadata only. The server verifies the actual access token.
        var email: String?
        var subscriptionEnd: Date?
        if let jwt = tokens["id_token"] as? String {
            let parts = jwt.split(separator: ".")
            if parts.count == 3 {
                var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
                if let decoded = Data(base64Encoded: payload),
                   let claims = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] {
                    email = claims["email"] as? String
                    let auth = claims["https://api.openai.com/auth"] as? [String: Any]
                    subscriptionEnd = SubscriptionMetadata.activeUntil(auth?["chatgpt_subscription_active_until"])
                }
            }
        }
        return (token, tokens["account_id"] as? String ?? "", email, subscriptionEnd)
    }

    static func fetch(account: UsageAccount = .currentCodex) async -> ProviderSnapshot {
        var snap = ProviderSnapshot()
        do {
            let path = account.configDirectory == nil ? authPath : account.directory.appendingPathComponent("auth.json")
            guard let credentialData = try? Data(contentsOf: path) else {
                throw UsageError.message("No local Codex login found. Use Sign in for this account.")
            }
            let (token, accountID, email, subscriptionEnd) = try credentials(from: credentialData)
            snap.identityLabel = email
            snap.accountIdentity = SubscriptionMetadata.identity(provider: .codex, account: accountID.isEmpty ? email : accountID)
            snap.subscriptionActiveUntil = subscriptionEnd
            snap.credentialFingerprint = SHA256.hash(data: Data((token + "\0" + accountID).utf8))
                .map { String(format: "%02x", $0) }.joined()
            var req = URLRequest(url: usageURL)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if !accountID.isEmpty { req.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id") }
            req.timeoutInterval = 15

            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            if code == 401 || code == 403 {
                throw UsageError.message("Login needs attention. Open Codex for this account, or use Sign in.")
            }
            if code == 429 {
                snap.retryAfter = HTTPHint.retryAfter(http)
                throw UsageError.message("Rate limited — backing off.")
            }
            guard code == 200 else { throw UsageError.message("HTTP \(code)") }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw UsageError.message("Bad response.")
            }

            snap.plan = (json["plan_type"] as? String)?.capitalized
            snap.fetchedAt = Date()

            if let rl = json["rate_limit"] as? [String: Any] {
                for (key, fallback) in [("primary_window", "Primary"), ("secondary_window", "Secondary")] {
                    guard let w = rl[key] as? [String: Any],
                          let pct = w["used_percent"] as? Double else { continue }
                    snap.meters.append(Meter(
                        id: "codex.\(key)",
                        label: windowLabel(w["limit_window_seconds"] as? Double) ?? fallback,
                        percent: pct,
                        resetsAt: (w["reset_at"] as? Double).map { Date(timeIntervalSince1970: $0) },
                        isActive: key == "primary_window"
                    ))
                }
            }

            if let c = json["credits"] as? [String: Any] {
                if c["unlimited"] as? Bool == true {
                    snap.note = "Unlimited credits"
                } else if let bal = c["balance"] as? Double, c["has_credits"] as? Bool == true {
                    snap.note = "Credits balance \(Int(bal))"
                }
            }
        } catch let e as UsageError {
            snap.error = e.text
        } catch {
            snap.error = error.localizedDescription
        }
        return snap
    }

    private static func windowLabel(_ seconds: Double?) -> String? {
        guard let s = seconds else { return nil }
        switch Int(s) {
        case 604800: return "Weekly"
        case 86400: return "Daily"
        case 18000: return "Session · 5h"
        case 3600: return "Hourly"
        default:
            let h = Int(s) / 3600
            return h >= 24 ? "Rolling · \(h / 24)d" : "Rolling · \(h)h"
        }
    }
}

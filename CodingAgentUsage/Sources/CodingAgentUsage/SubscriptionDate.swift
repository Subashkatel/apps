import Foundation
import CryptoKit

enum SubscriptionDateKind: String, Codable, CaseIterable {
    case renewal, end
    var title: String { self == .renewal ? "Renews on" : "Ends on" }
}

/// A calendar date, not an instant: moving time zones must not change the saved day.
struct SavedSubscriptionDate: Codable, Equatable {
    var day: String
    var kind: SubscriptionDateKind

    private static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
    init(date: Date, kind: SubscriptionDateKind) {
        day = Self.formatter.string(from: date)
        self.kind = kind
    }
    var date: Date? {
        guard let date = Self.formatter.date(from: day), Self.formatter.string(from: date) == day else { return nil }
        return date
    }
}

enum SubscriptionMetadata {
    /// Persist an opaque stable identity, never the credential or raw account ID.
    static func identity(provider: UsageProvider, account: String?, organization: String? = nil) -> String? {
        guard let account, !account.isEmpty else { return nil }
        let value = provider.rawValue + "\0" + account + "\0" + (organization ?? "")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func activeUntil(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

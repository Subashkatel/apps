import Foundation

/// Settings are local files, never fetched. Environment overrides also make tests isolated.
public enum LocalConfig {
    public static var configURL: URL {
        if let path = ProcessInfo.processInfo.environment["LOCAL_APPS_CONFIG"] {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/local-apps/config.json")
    }
    public static func string(_ key: String, environment: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[environment], !value.isEmpty { return value }
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = config[key] as? String, !value.isEmpty else { return nil }
        return value
    }
    public static func path(_ key: String, environment: String) -> URL? {
        guard let raw = string(key, environment: environment) else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded)
    }
    public static func executable(_ key: String, environment: String, name: String) -> URL? {
        // An explicit but invalid override must not silently run another executable.
        if string(key, environment: environment) != nil {
            guard let url = path(key, environment: environment),
                  FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
            return url
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
            + [home + "/.local/bin", home + "/Library/Application Support/LocalApps/GeminiCLI/node_modules/.bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    public static func dataDirectory(_ app: String) -> URL {
        let root = path("dataRoot", environment: "LOCAL_APPS_DATA_ROOT")
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent(app, isDirectory: true)
    }
}

public enum LocalFiles {
    /// A basename from imported metadata must never become an arbitrary path.
    public static func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
    }
    /// Write the replacement successfully before retiring an earlier filename.
    public static func replace(_ text: String, at destination: URL, retiring old: URL? = nil) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: destination, atomically: true, encoding: .utf8)
        if let old, old.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath(), FileManager.default.fileExists(atPath: old.path) {
            try FileManager.default.removeItem(at: old)
        }
    }
}

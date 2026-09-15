import Foundation
import Security

public enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case claude, codex, gemini, server
    public var id: Self { self }
    public var title: String {
        switch self { case .claude: "Claude"; case .codex: "Codex"; case .gemini: "Gemini (Antigravity)"; case .server: "Custom server" }
    }
}

public struct AISettings: Codable, Equatable {
    public init() {}
    public var provider = AIProvider.claude
    public var claudeModel = ""
    public var codexModel = ""
    public var geminiModel: String? = nil
    public var geminiExecutablePath: String? = nil
    public var serverModel = ""
    public var endpoint = ""
    public var executablePath = ""
    public var codexExecutablePath = ""

    public static var fileURL: URL { LocalConfig.dataDirectory("Frontier").appendingPathComponent("ai-settings.json") }
    public static func load(from url: URL = fileURL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        var settings = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        if let old = settings.geminiExecutablePath, URL(fileURLWithPath: old).lastPathComponent == "gemini" { settings.geminiExecutablePath = nil }
        return settings
    }
    public func save(to url: URL = fileURL) throws {
        _ = try validated()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        NotificationCenter.default.post(name: .localAISettingsChanged, object: url)
    }
    public var model: String {
        let selected = switch provider { case .claude: claudeModel; case .codex: codexModel; case .gemini: geminiModel ?? ""; case .server: serverModel }
        return selected.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public var modelLabel: String {
        model.isEmpty ? (provider == .server ? "Model not configured" : "CLI default") : model
    }
    public var selectionLabel: String { provider.title + " · " + modelLabel }
    public var executable: URL? {
        guard provider != .server else { return nil }
        var override = provider == .claude ? executablePath : provider == .gemini ? (geminiExecutablePath ?? "") : codexExecutablePath
        // Older versions stored the retired Gemini CLI path. Resolve its supported successor.
        if provider == .gemini, URL(fileURLWithPath: override).lastPathComponent == "gemini" { override = "" }
        if !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
        if provider == .gemini { return LocalConfig.executable("antigravityPath", environment: "LOCAL_APPS_ANTIGRAVITY", name: "agy") }
        return LocalConfig.executable(provider.rawValue + "Path", environment: "LOCAL_APPS_" + provider.rawValue.uppercased(), name: provider.rawValue)
    }
    public func serverURL() throws -> URL {
        guard var parts = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw LocalAIError("Enter an HTTP or HTTPS API base URL without a password, query, or fragment.")
        }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        parts.path = path
        guard let url = parts.url else { throw LocalAIError("The API URL is invalid.") }
        return url
    }
    public func validated() throws -> Self {
        if provider == .server {
            _ = try serverURL()
            guard !serverModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalAIError("Enter the model name used by your server.") }
        } else if executable == nil { throw LocalAIError("\(provider.title) was not found. Select its executable or install the CLI first.") }
        return self
    }

    public func arguments() -> [String] {
        var args: [String]
        if provider == .claude {
            args = ["-p", "--output-format", "text", "--tools", "", "--strict-mcp-config", "--safe-mode", "--no-session-persistence"]
        } else if provider == .gemini {
            args = ["--input-format", "stream-json", "--output-format", "stream-json", "--disable-slash-commands", "--mode", "plan", "--sandbox"]
        } else {
            args = ["exec", "--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "--sandbox", "read-only",
                    "-c", "approval_policy=\"never\"", "-c", "web_search=\"disabled\"", "-c", "features.shell_tool=false", "-c", "features.multi_agent=false", "-c", "features.apps=false",
                    "--color", "never"]
        }
        if !model.isEmpty { args += ["--model", model] }
        if provider == .codex { args.append("-") }
        return args
    }
}

public enum AIKeychain {
    private static func query(_ endpoint: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.frontier.ai",
         kSecAttrAccount as String: endpoint.absoluteString]
    }
    public static func read(for endpoint: URL) throws -> String? {
        var q = query(endpoint); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw LocalAIError("Could not read the API key from Keychain (\(status)).") }
        return String(data: data, encoding: .utf8)
    }
    public static func save(_ key: String, for endpoint: URL) throws {
        let q = query(endpoint)
        if key.isEmpty {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw LocalAIError("Could not remove the API key (\(status)).") }
            return
        }
        let value = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(q as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(q.merging(value, uniquingKeysWith: { _, new in new }) as CFDictionary, nil) == errSecSuccess else {
                throw LocalAIError("Could not save the API key in Keychain.")
            }
        } else if status != errSecSuccess { throw LocalAIError("Could not update the API key (\(status)).") }
    }
}

public enum AIClient {
    public static func request(settings: AISettings, prompt: String, key: String?, timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: try settings.serverURL(), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": settings.serverModel,
            "messages": [["role": "user", "content": prompt]], "stream": false])
        return request
    }
    public static func response(_ data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else {
            throw LocalAIError(status == 401 || status == 403 ? "Server authentication failed. Check the saved API key." : "The AI server returned HTTP \(status).")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let text = message?["content"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalAIError("The AI server returned no text. Use a model that supports Chat Completions.")
        }
        if choices?.first?["finish_reason"] as? String == "length" { throw LocalAIError("The model's response was cut short. Increase its output limit or use a smaller import.") }
        return text
    }
    public static func ask(_ prompt: String, settings: AISettings, timeout: TimeInterval) throws -> String {
        _ = try settings.validated()
        if settings.provider != .server {
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("frontier-ai-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            var environment: [String: String]? = nil
            var input = Data(prompt.utf8)
            if settings.provider == .gemini {
                environment = ProcessInfo.processInfo.environment
                environment?["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
                let searchPath = (environment?["PATH"] ?? "/usr/bin:/bin") + ":/opt/homebrew/bin:/usr/local/bin"
                environment?["PATH"] = searchPath
                let turn: [String: Any] = ["event": "user", "message": ["content": prompt]]
                input = try JSONSerialization.data(withJSONObject: turn); input.append(10)
            }
            let data = try LocalProcess.run(settings.executable!, arguments: settings.arguments(), input: input, directory: scratch, timeout: timeout, environment: environment)
            if settings.provider == .gemini { return try antigravityResponse(data) }
            guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalAIError("\(settings.provider.title) returned no text. Check its login and model.") }
            return text
        }
        let request = try request(settings: settings, prompt: prompt, key: AIKeychain.read(for: settings.serverURL()), timeout: timeout)
        return try send(request, timeout: timeout)
    }
    public static func antigravityResponse(_ data: Data) throws -> String {
        let records = data.split(separator: 10).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
        guard let result = records.last(where: { $0["event"] as? String == "result" })?["result"] as? [String: Any] else {
            throw LocalAIError("Antigravity stopped before returning a completed answer. Please try again.")
        }
        // JSON null bridges to NSNull, not nil. Current CLI releases include it
        // on successful responses; older releases omit the error field.
        let hasError = result["error"] != nil && !(result["error"] is NSNull)
        guard result["status"] as? String == "SUCCESS", !hasError else {
            switch result["status"] as? String {
            case "CANCELED", "INTERRUPTED":
                throw LocalAIError("Antigravity was interrupted before completing the answer. Please try again.")
            case "WAITING":
                throw LocalAIError("Antigravity stopped while waiting for input or permission. Try again with a question it can answer from the supplied text.")
            default:
                throw LocalAIError("Antigravity could not complete this answer. Please try again; if it keeps failing, check the connection and selected model in AI settings.")
            }
        }
        guard let answer = result["response"] as? String, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalAIError("Antigravity completed the request but returned no answer. Please try again.")
        }
        return answer
    }
    public static func send(_ request: URLRequest, timeout: TimeInterval) throws -> String {
        let done = DispatchSemaphore(value: 0), result = HTTPResult()
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: request) { data, response, error in
            result.data = data; result.status = (response as? HTTPURLResponse)?.statusCode ?? 0; result.error = error
            done.signal()
        }
        task.resume()
        guard done.wait(timeout: .now() + timeout + 1) == .success else { task.cancel(); throw LocalAIError("The AI server timed out.") }
        if let error = result.error { throw error }
        return try response(result.data ?? Data(), status: result.status)
    }
    private final class HTTPResult: @unchecked Sendable {
        var data: Data?; var status = 0; var error: Error?
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

import AppKit

public extension AISettings {
    func openLogin() throws {
        guard let executable else { throw LocalAIError("Install the CLI or select its executable first.") }
        let suffix = provider == .claude ? " auth login" : provider == .codex ? " login" : ""
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("local-app-login-" + UUID().uuidString)
        let command = "#!/bin/zsh\nexport PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin\"\ncd '" + folder.path.replacingOccurrences(of: "'", with: "'\\''") + "' || exit 1\nexec '" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'" + suffix + "\n"
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = folder.appendingPathComponent("Sign in to \(provider.title).command")
        try command.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        guard NSWorkspace.shared.open(script) else { throw LocalAIError("Terminal could not be opened. Start your provider's login command in Terminal.") }
    }
}

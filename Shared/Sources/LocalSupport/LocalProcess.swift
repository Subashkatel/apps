import Foundation

public struct LocalAIError: LocalizedError {
    var message: String
    public var retryable: Bool
    public var errorDescription: String? { message }
    public init(_ message: String, retryable: Bool = false) { self.message = message; self.retryable = retryable }
}

/// Cancellation belongs to one request, never to other apps or summary jobs.
public final class AICancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func cancel() { lock.lock(); stopped = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    public func check() throws { if isCancelled { throw CancellationError() } }
}

/// Bounded, concurrent pipe draining prevents a long book or CLI error from deadlocking.
public enum LocalProcess {
    final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var exceeded = false
        func append(_ bytes: Data, limit: Int) {
            lock.lock(); defer { lock.unlock() }
            if data.count + bytes.count > limit { exceeded = true }
            data.append(bytes.prefix(max(0, limit - data.count)))
        }
        var value: Data { lock.lock(); defer { lock.unlock() }; return data }
        var overflow: Bool { lock.lock(); defer { lock.unlock() }; return exceeded }
    }

    public static func run(_ executable: URL, arguments: [String], input: Data = Data(),
                    directory: URL? = nil, timeout: TimeInterval = 30, limit: Int = 20_000_000, environment: [String: String]? = nil, cancellation: AICancellation? = nil) throws -> Data {
        try cancellation?.check()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.currentDirectoryURL = directory
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        let out = Buffer(), err = Buffer(), group = DispatchGroup()
        try process.run()
        for (pipe, buffer) in [(stdout, out), (stderr, err)] {
            DispatchQueue.global().async(group: group) {
                while let bytes = try? pipe.fileHandleForReading.read(upToCount: 32_768), !bytes.isEmpty {
                    buffer.append(bytes, limit: limit)
                }
            }
        }
        DispatchQueue.global().async(group: group) {
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline && !out.overflow && !err.overflow && cancellation?.isCancelled != true { Thread.sleep(forTimeInterval: 0.02) }
        let interrupted = process.isRunning
        if interrupted {
            process.terminate()
            let grace = Date().addingTimeInterval(1)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        _ = group.wait(timeout: .now() + 2)
        try cancellation?.check()
        if out.overflow || err.overflow { throw LocalAIError("The document or response exceeds the supported size.") }
        if interrupted { throw LocalAIError("The operation timed out. Try a smaller document or check your AI connection.") }
        guard process.terminationStatus == 0 else {
            if executable.lastPathComponent == "agy", AIClient.hasAntigravityResult(out.value) {
                // Preserve structured provider errors even when the CLI exits nonzero.
                _ = try AIClient.antigravityResponse(out.value)
            }
            let failure = (String(data: out.value, encoding: .utf8) ?? "") + (String(data: err.value, encoding: .utf8) ?? "")
            let message = failure.lowercased()
            if ["claude", "codex", "gemini", "agy"].contains(executable.lastPathComponent) {
                if message.contains("hit your") && message.contains("limit") || message.contains("rate limit") || message.contains("usage limit") {
                    throw LocalAIError("This AI account has reached its usage limit. Try again after it resets, or choose another provider in AI settings.")
                }
                if message.contains("this client is no longer supported") {
                    throw LocalAIError("Google retired personal-account access through Gemini CLI. Choose Gemini (Antigravity) in AI settings and sign in using agy.")
                }
                if message.contains("authentication required") || message.contains("not logged in") || message.contains("authentication failed") || message.contains("please log in") {
                    throw LocalAIError("Sign in to \(executable.lastPathComponent) in Terminal, then try again.")
                }
            }
            // CLI output can contain source excerpts; keep it out of logs and error alerts.
            throw LocalAIError("\(executable.lastPathComponent) exited with status \(process.terminationStatus). Check its login and configuration, or whether the file is readable.")
        }
        return out.value
    }
}

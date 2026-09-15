import LocalSupport
import Foundation

struct VBError: Error { let text: String
    static func message(_ s: String) -> VBError { VBError(text: s) }
}

/// Everything tunable lives in plain files under ~/.config/voicebridge so the
/// vocabulary and fix-ups can be edited without rebuilding the app.
enum Config {
    static let dir = LocalConfig.path("voiceConfigDirectory", environment: "VOICEBRIDGE_CONFIG_DIR")
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/voicebridge")
    static var vocabularyURL: URL { dir.appendingPathComponent("vocabulary.txt") }
    static var replacementsURL: URL { dir.appendingPathComponent("replacements.txt") }

    static let support = LocalConfig.dataDirectory("VoiceBridge")
    static var modelURL: URL {
        LocalConfig.path("whisperModel", environment: "WHISPER_MODEL")
            ?? support.appendingPathComponent("ggml-small.en.bin")
    }

    static var whisperCLI: URL? {
        LocalConfig.executable("whisperCLI", environment: "WHISPER_CLI", name: "whisper-cli")
    }

    // MARK: - Defaults written on first launch

    private static let defaultVocabulary = "# Add words the recognizer gets wrong, such as names and technical terms.\n"

    private static let defaultReplacements = "# Add corrections, one per line: wrong => right\n"

    static func bootstrap() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: vocabularyURL.path) {
            try? defaultVocabulary.write(to: vocabularyURL, atomically: true, encoding: .utf8)
        }
        if !fm.fileExists(atPath: replacementsURL.path) {
            try? defaultReplacements.write(to: replacementsURL, atomically: true, encoding: .utf8)
        }
    }

    /// Comment lines are stripped; the rest is collapsed into one priming string.
    static func vocabularyPrompt() -> String {
        let raw = (try? String(contentsOf: vocabularyURL, encoding: .utf8)) ?? defaultVocabulary
        let body = raw.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: " ")
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// whisper truncates the initial prompt near 224 tokens and drops the overflow
    /// silently, so an oversized vocabulary quietly stops working. This is a rough
    /// estimate — whisper uses a GPT-2-style BPE, and ~3.5 characters per token errs
    /// slightly high for technical jargon, which is the safe direction.
    static let promptTokenLimit = 224

    static func approximateTokenCount(_ text: String) -> Int {
        max(1, Int((Double(text.count) / 3.5).rounded()))
    }

    static func replacements() -> [(String, String)] {
        let raw = (try? String(contentsOf: replacementsURL, encoding: .utf8)) ?? defaultReplacements
        return raw.split(separator: "\n").compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, !s.hasPrefix("#"), s.contains("=>") else { return nil }
            let parts = s.components(separatedBy: "=>")
            guard parts.count == 2 else { return nil }
            let from = parts[0].trimmingCharacters(in: .whitespaces)
            let to = parts[1].trimmingCharacters(in: .whitespaces)
            return from.isEmpty ? nil : (from, to)
        }
    }
}

enum Prefs {
    private static let d = UserDefaults.standard
    /// Off by default: you see the text in the prompt and press Return yourself.
    static var autoSubmit: Bool {
        get { d.bool(forKey: "autoSubmit") }
        set { d.set(newValue, forKey: "autoSubmit") }
    }

    /// Where the transcript goes. Defaults to wherever the cursor is.
    static var target: DeliveryTarget {
        get { DeliveryTarget(rawValue: d.string(forKey: "target") ?? "") ?? .focused }
        set { d.set(newValue.rawValue, forKey: "target") }
    }
}

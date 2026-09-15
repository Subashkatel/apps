import Foundation
import LocalSupport

struct MeetingError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
enum CaptureMode: String, Codable, CaseIterable, Identifiable {
    case microphone, call
    var id: Self { self }
    var title: String { self == .microphone ? "Microphone only · in person" : "Microphone + system audio" }
}
enum MeetingPhase: String, Codable {
    case recording, recorded, transcribing, ready, failed, interrupted
    var title: String {
        switch self { case .recording: "Recording"; case .recorded: "Recording saved"; case .transcribing: "Transcribing"; case .ready: "Transcript ready"; case .failed: "Needs attention"; case .interrupted: "Recording interrupted" }
    }
}
struct Segment: Codable, Identifiable, Equatable {
    var id: String
    var track: String
    var start: Double
    var end: Double
    var text: String
    var speaker: String { track == "mic" ? "Microphone" : "System audio" }
    var time: String { Self.timestamp(start) }
    static func timestamp(_ seconds: Double) -> String {
        let s = max(0, Int(seconds)); return s >= 3600 ? String(format: "%d:%02d:%02d", s/3600, s/60%60, s%60) : String(format: "%02d:%02d", s/60, s%60)
    }
}
struct TaskChange: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var existingID: String?
    var expectedRevision: Int?
    var title: String
    var owner: String
    var due: String?
    var dueTime: String?
    var evidence: [String]
    var accepted = true
}
struct MeetingDraft: Codable, Equatable {
    var summary: String
    var decision: String
    var question: String
    var changes: [TaskChange]
    var relatedMeetingID: String?
    var relatedReason: String?
    var evidence: [String]
    var provider: String
    var model: String
    var created = Date()
    var applied = false
    var appliedTaskIDs: [String] = []
    var originalNotes: String
    var sourceTranscript: [Segment]?
    var suggestedTitle: String?
    var contextMeetingIDs: [String]?
    var omittedContextCount: Int?
}
struct Meeting: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var created = Date()
    var ended: Date?
    var projectID: String?
    var mode: CaptureMode
    var phase: MeetingPhase = .recording
    var notes = ""
    var transcript: [Segment] = []
    var offsets: [String: Double] = [:]
    var captureIssue: String?
    var error: String?
    var draft: MeetingDraft?
    var deletedAt: Date?
    var titleEdited: Bool?
    var attachments: [MeetingAttachment]?
    mutating func receiveDraft(_ value:MeetingDraft,requestedTitle:String) {
        if titleEdited != true, title==requestedTitle, (title.hasPrefix("Meeting · ") || titleEdited==false),let suggested=value.suggestedTitle,!suggested.isEmpty {
            title=String(suggested.prefix(160));titleEdited=false
        }
        draft=value;error=nil
    }
    var duration: Double { max(0, (ended ?? Date()).timeIntervalSince(created)) }
}
struct MeetingProject: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var question = ""
}
struct WorkTask: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var projectID: String?
    var title: String
    var owner: String
    var due: String?
    var dueTime: String?
    var done = false
    var revision = 0
    var meetingID: String?
    var history: [String] = []
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?
    var deletedWithMeetingID: String?
}
struct Preferences: Codable {
    var mode: CaptureMode = .microphone
    var whisperPath = ""
    var modelPath = ""
    var language = "en"
    var style = "Keep it direct and natural. Use my wording when appropriate. Preserve uncertainty. Use ‘I’ only for things I clearly said or agreed to. Do not invent owners, dates, decisions, or confidence. No corporate filler."
    var example = ""
    var animateBear = true
    var globalShortcuts = true
    var shortcutExtraCommand = false
    var autoTranscribe = true
    var echoCancellation = false
    var preferredProject: String?
    var appearance = "dark"
    var ai = AISettings()
    static var root: URL { LocalConfig.dataDirectory("Meeting Notes") }
    var whisper: URL? {
        if !whisperPath.isEmpty { let u = URL(fileURLWithPath: (whisperPath as NSString).expandingTildeInPath); return FileManager.default.isExecutableFile(atPath: u.path) ? u : nil }
        return LocalConfig.executable("whisperCLI", environment: "WHISPER_CLI", name: "whisper-cli")
    }
    var model: URL {
        if !modelPath.isEmpty { return URL(fileURLWithPath: (modelPath as NSString).expandingTildeInPath) }
        return LocalConfig.path("whisperModel", environment: "WHISPER_MODEL") ?? LocalConfig.dataDirectory("VoiceBridge").appendingPathComponent("ggml-small.en.bin")
    }
}

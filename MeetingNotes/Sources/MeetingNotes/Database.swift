import Foundation
import CSQLite

/// SQLite transactions commit the note and project changes together. Failed writes
/// never publish the replacement into the UI. WAL permits recovery after a crash.
final class Database {
    private var handle: OpaquePointer?
    let root: URL
    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent("meetings.sqlite")
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw MeetingError("Could not open the meeting database.") }
        sqlite3_busy_timeout(handle, 3000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS records(kind TEXT NOT NULL,id TEXT NOT NULL,json BLOB NOT NULL,PRIMARY KEY(kind,id));")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    deinit { sqlite3_close(handle) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw MeetingError("Could not save meeting data: " + String(cString: sqlite3_errmsg(handle))) }
    }
    func transaction(_ action: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try action(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func put<T: Encodable>(_ item: T, kind: String, id: String) throws {
        let data = try JSONEncoder().encode(item)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "INSERT INTO records(kind,id,json) VALUES(?,?,?) ON CONFLICT(kind,id) DO UPDATE SET json=excluded.json", -1, &statement, nil) == SQLITE_OK else { throw MeetingError("Could not prepare the database write.") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, kind, -1, transient); sqlite3_bind_text(statement, 2, id, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw MeetingError("Could not save: " + String(cString: sqlite3_errmsg(handle))) }
    }
    func list<T: Decodable>(_ type: T.Type, kind: String) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT json FROM records WHERE kind=?", -1, &statement, nil) == SQLITE_OK else { throw MeetingError("Could not read the database.") }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, kind, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var values: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw MeetingError("The saved data could not be read. It has not been replaced.") }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            values.append(try JSONDecoder().decode(T.self, from: data))
        }
        return values
    }
    func backup(force:Bool = false) throws {
        let directory = root.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let date = DateFormatter(); date.dateFormat=force ? "yyyy-MM-dd-HHmmss":"yyyy-MM-dd"; date.locale=Locale(identifier:"en_US_POSIX")
        let destination = directory.appendingPathComponent(date.string(from:Date())+".sqlite")
        if FileManager.default.fileExists(atPath:destination.path) { return }
        let temporary = directory.appendingPathComponent(UUID().uuidString+".sqlite")
        var target: OpaquePointer?
        guard sqlite3_open(temporary.path,&target)==SQLITE_OK else {throw MeetingError("Could not create a database backup.")}
        defer{sqlite3_close(target)}
        guard let copy = sqlite3_backup_init(target,"main",handle,"main") else{throw MeetingError("Could not start a database backup.")}
        let result=sqlite3_backup_step(copy,-1),finish=sqlite3_backup_finish(copy)
        guard result==SQLITE_DONE,finish==SQLITE_OK else{throw MeetingError("Could not finish the database backup.")}
        try FileManager.default.moveItem(at:temporary,to:destination)
    }
    func archive(_ meeting: Meeting) throws {
        let directory=folder(meeting.id)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(meeting).write(to:directory.appendingPathComponent("meeting.json"),options:.atomic)
        if !meeting.transcript.isEmpty {
            let transcriptURL=directory.appendingPathComponent("transcript.json")
            let data=try encoder.encode(meeting.transcript)
            if let previous=try? Data(contentsOf:transcriptURL),previous != data {
                let versions=directory.appendingPathComponent("Transcript versions")
                try FileManager.default.createDirectory(at:versions,withIntermediateDirectories:true)
                try previous.write(to:versions.appendingPathComponent(UUID().uuidString+".json"),options:.atomic)
            }
            try data.write(to:transcriptURL,options:.atomic)
            let text=meeting.transcript.map{"[\($0.time)] \($0.speaker): \($0.text)"}.joined(separator:"\n\n")
            try text.write(to:directory.appendingPathComponent("transcript.txt"),atomically:true,encoding:.utf8)
        }
        try meeting.notes.write(to:directory.appendingPathComponent("my-notes.txt"),atomically:true,encoding:.utf8)
    }
    func folder(_ id: String) -> URL { root.appendingPathComponent("Recordings", isDirectory: true).appendingPathComponent(id, isDirectory: true) }
}

/// Pure reconciliation is also used by tests. Stable IDs and revisions prevent
/// duplicate tasks and overwriting a task changed while AI was working.
enum Reconcile {
    static func apply(meeting: Meeting, tasks: [WorkTask]) throws -> (Meeting, [WorkTask]) {
        guard meeting.deletedAt==nil else{throw MeetingError("Restore this meeting before saving changes.")}
        guard var draft = meeting.draft else { throw MeetingError("There is no draft to save.") }
        guard !draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MeetingError("Write a short summary before saving.") }
        if draft.applied { return (meeting, tasks) }
        var result = tasks
        do {
            let project = meeting.projectID
            for change in draft.changes where change.accepted {
                let title = change.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { throw MeetingError("Give each selected task an action, or uncheck it.") }
                if let due=change.due,!Summarizer.validDate(due){throw MeetingError("Use YYYY-MM-DD for due dates, or leave the date empty.")}
                if let time=change.dueTime,change.due == nil || !Summarizer.validTime(time){throw MeetingError("Set a due date and a valid HH:mm time, or leave time empty.")}
                let history = Date().formatted(date: .abbreviated, time: .omitted) + ": " + title
                if let id = change.existingID {
                    guard let index = result.firstIndex(where: { $0.id == id && $0.deletedAt==nil && $0.projectID == project && (project != nil || $0.meetingID == meeting.id) }), result[index].revision == change.expectedRevision, !result[index].done else {
                        throw MeetingError("A proposed task has changed since the draft was made. Uncheck that update and save the other changes, or generate a new draft.")
                    }
                    result[index].title = title; result[index].owner = change.owner; result[index].due = change.due; result[index].dueTime = change.dueTime; result[index].updatedAt = Date()
                    result[index].meetingID = meeting.id; result[index].revision += 1; result[index].history.append(history)
                    draft.appliedTaskIDs.append(id)
                } else {
                    let id = meeting.id + ":" + change.id
                    if !result.contains(where: { $0.id == id }) {
                        result.append(WorkTask(id: id, projectID: project, title: title, owner: change.owner, due: change.due, dueTime: change.dueTime, meetingID: meeting.id, history: [history], createdAt:Date(),updatedAt:Date()))
                    }
                    draft.appliedTaskIDs.append(id)
                }
            }
        }
        draft.applied = true
        var updated = meeting; updated.draft = draft
        return (updated, result)
    }
}

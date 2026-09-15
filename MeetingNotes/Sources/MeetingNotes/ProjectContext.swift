import Foundation

struct ProjectContext {
    struct Entry:Codable {
        var id:String,title:String,date:String,summary:String,decision:String,question:String,notes:String
    }
    let entries:[Entry]
    let eligible:Int
    var omitted:Int{eligible-entries.count}
    var json:String{String(decoding:(try? JSONEncoder().encode(entries)) ?? Data("[]".utf8),as:UTF8.self)}
    static func make(for meeting:Meeting,from meetings:[Meeting],limit:Int=80_000)->ProjectContext {
        let all=meetings.filter{$0.id != meeting.id && meeting.projectID != nil && $0.projectID==meeting.projectID && $0.deletedAt==nil && ($0.draft?.applied==true || !$0.notes.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}.sorted{$0.created>$1.created}
        var result:[Entry]=[],bytes=2
        for m in all {
            let d=m.draft?.applied==true ? m.draft:nil
            let entry=Entry(id:m.id,title:m.title,date:m.created.formatted(.iso8601),summary:d?.summary ?? "",decision:d?.decision ?? "",question:d?.question ?? "",notes:m.notes)
            let size=(try? JSONEncoder().encode(entry).count) ?? limit+1
            if bytes+size+1<=limit {result.append(entry);bytes+=size+1}
        }
        return ProjectContext(entries:result,eligible:all.count)
    }
}

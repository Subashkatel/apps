import Foundation

struct TaskQuery {
    static var today:String {let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";return f.string(from:Date())}
    var search="",project="all",meeting="all",status="open",deadline="all",sort="due"
    func results(_ tasks:[WorkTask],today:String=TaskQuery.today)->[WorkTask] {
        tasks.filter {t in
            t.deletedAt==nil &&
            (project=="all" || (project=="unfiled" ? t.projectID==nil:t.projectID==project)) &&
            (meeting=="all" || (meeting=="none" ? t.meetingID==nil:t.meetingID==meeting)) &&
            (status=="all" || (status=="done" ? t.done:!t.done)) &&
            (search.isEmpty || (t.title+" "+t.owner).localizedCaseInsensitiveContains(search)) &&
            (deadline=="all" || (deadline=="none" ? t.due==nil:deadline=="today" ? t.due==today:(t.due.map{$0<today && !t.done} ?? false)))
        }.sorted {a,b in
            if a.done != b.done{return !a.done}
            if sort=="newest" {let x=a.createdAt ?? .distantPast,y=b.createdAt ?? .distantPast;if x != y{return x>y}}
            if sort=="due" {let x=(a.due ?? "9999-99-99")+(a.dueTime ?? "23:59"),y=(b.due ?? "9999-99-99")+(b.dueTime ?? "23:59");if x != y{return x<y}}
            let compare=a.title.localizedStandardCompare(b.title)
            return compare == .orderedSame ? a.id<b.id:compare == .orderedAscending
        }
    }
}

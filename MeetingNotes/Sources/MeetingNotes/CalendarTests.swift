import Foundation

@MainActor enum CalendarTests {
    static func run() throws {
        let zone=TimeZone(identifier:"America/New_York")!
        let task=WorkTask(title:"Review, compare; Δ & A+B",owner:"Me",due:"2026-03-08")
        let draft=CalendarDraft.task(task,project:"Example",timeZone:zone)
        try SelfTests.require(draft.dateConfirmed && draft.allDay,"Date-only task was not an all-day event")
        let bytes=try draft.ics(),ics=String(decoding:bytes,as:UTF8.self)
        try SelfTests.require(ics.contains("DTSTART;VALUE=DATE:20260308\r\nDTEND;VALUE=DATE:20260309"),"All-day date range shifted across DST")
        let link=try draft.googleURL(),parts=URLComponents(url:link,resolvingAgainstBaseURL:false)!.queryItems!
        try SelfTests.require(parts.first{$0.name=="dates"}?.value=="20260308/20260309","Google all-day end is not exclusive")
        try SelfTests.require(parts.first{$0.name=="text"}?.value==task.title,"Calendar link did not encode title safely")
        try SelfTests.require(link.absoluteString.contains("%2B"),"A plus sign could be decoded as a space by Google")
        let timed=CalendarDraft.task(WorkTask(title:"Due at 9",owner:"",due:"2026-03-08",dueTime:"09:00"),project:nil,timeZone:zone)
        let timedICS=String(decoding:try timed.ics(),as:UTF8.self)
        try SelfTests.require(timedICS.contains("DTSTART:20260308T130000Z") && timedICS.contains("DTEND:20260308T133000Z"),"Timed task timezone or duration is wrong")
        let noDate=CalendarDraft.task(WorkTask(title:"Unscheduled",owner:""),project:nil)
        let invalidDate=CalendarDraft.task(WorkTask(title:"Invalid date",owner:"",due:"2026-02-30"),project:nil)
        try SelfTests.require(!noDate.dateConfirmed && !invalidDate.dateConfirmed,"Invented a calendar date for an unscheduled/invalid task")
        for invalid in [noDate,invalidDate] {
            var rejected=false;do{_ = try invalid.ics()}catch{rejected=true}
            try SelfTests.require(rejected,"Unconfirmed calendar date was accepted")
        }
        var text=draft;text.title=String(repeating:"研究🙂",count:80)+"\r\nBEGIN:VEVENT";text.details="line one\nline two; comma, backslash\\"
        let folded=String(decoding:try text.ics(),as:UTF8.self)
        try SelfTests.require(folded.components(separatedBy:"\r\n").allSatisfy{$0.utf8.count<=75},"iCalendar folding splits or exceeds 75-byte lines")
        let unfolded=folded.replacingOccurrences(of:"\r\n ",with:"")
        try SelfTests.require(unfolded.contains("\\nBEGIN:VEVENT") && !unfolded.contains("\r\nBEGIN:VEVENT\r\nBEGIN:VEVENT"),"Calendar title allowed an injected line")
        try SelfTests.require(unfolded.contains("DESCRIPTION:line one\\nline two\\; comma\\, backslash\\\\"),"Calendar description escaping failed")
        var invalid=timed;invalid.end=invalid.start;try SelfTests.require(invalid.validation != nil,"Zero-length timed event accepted")
        invalid=timed;invalid.title="  ";try SelfTests.require(invalid.validation != nil,"Blank calendar title accepted")
        var long=draft;long.details=String(repeating:"long ",count:2000)
        var rejected=false;do{_ = try long.googleURL()}catch{rejected=true}
        let fallback=try long.ics()
        try SelfTests.require(rejected && !fallback.isEmpty,"Long URL has no usable export fallback")
        var meeting=Meeting(title:"Recorded meeting",mode:.microphone);meeting.created=timed.start;meeting.ended=timed.start.addingTimeInterval(7200)
        let meetingDraft=CalendarDraft.meeting(meeting,project:nil)
        try SelfTests.require(meetingDraft.end.timeIntervalSince(meetingDraft.start)==7200 && meetingDraft.details.isEmpty,"Meeting duration changed or private notes were copied")
        print("PASS calendar all-day/DST/timed ranges, URL encoding, iCalendar escaping/folding, missing-date validation and large-note export fallback")
    }
}

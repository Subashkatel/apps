import Foundation

/// A reviewed calendar copy; never changes the source meeting or task.
struct CalendarDraft: Identifiable {
    var id = UUID().uuidString
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var dateConfirmed = true
    var needsDate = false
    var details = ""
    var source: String
    var timeZone = TimeZone.current

    static func meeting(_ meeting: Meeting,project: String?) -> Self {
        Self(title:meeting.title,start:meeting.created,end:meeting.ended.flatMap{$0>meeting.created ? $0:nil} ?? meeting.created.addingTimeInterval(3600),allDay:false,details:project.map{"Project: "+$0} ?? "",source:"Meeting")
    }
    static func task(_ task: WorkTask,project:String?,now:Date=Date(),timeZone:TimeZone = .current)->Self {
        let format=formatter(task.dueTime == nil ? "yyyy-MM-dd":"yyyy-MM-dd HH:mm",timeZone:timeZone)
        let raw=task.due.map{$0+(task.dueTime.map{" "+$0} ?? "")}
        let parsed=raw.flatMap{value in format.date(from:value).flatMap{format.string(from:$0)==value ? $0:nil}}
        let start=parsed ?? now
        return Self(title:task.title,start:start,end:task.dueTime == nil ? start:start.addingTimeInterval(1800),allDay:task.dueTime == nil,dateConfirmed:parsed != nil,needsDate:parsed == nil,details:project.map{"Project: "+$0} ?? "",source:"Task",timeZone:timeZone)
    }
    var validation: String? {
        if title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{return "Give the event a title."}
        if !dateConfirmed{return "Choose a date for this calendar event."}
        var cal=Calendar(identifier:.gregorian);cal.timeZone=timeZone
        if allDay ? cal.startOfDay(for:end)<cal.startOfDay(for:start) : end<=start{return "The end must be after the start."}
        return nil
    }
    private var dateRange:(String,String) {
        if allDay {
            var cal=Calendar(identifier:.gregorian);cal.timeZone=timeZone
            let f=Self.formatter("yyyyMMdd",timeZone:timeZone)
            // iCalendar and Google both use an exclusive end for all-day events.
            return (f.string(from:start),f.string(from:cal.date(byAdding:.day,value:1,to:cal.startOfDay(for:end))!))
        }
        let f=Self.formatter("yyyyMMdd'T'HHmmss'Z'",timeZone:TimeZone(secondsFromGMT:0)!)
        return (f.string(from:start),f.string(from:end))
    }
    func googleURL() throws -> URL {
        if let validation{throw MeetingError(validation)}
        let dates=dateRange
        var url=URLComponents(string:"https://calendar.google.com/calendar/r/eventedit")!
        url.queryItems=[URLQueryItem(name:"action",value:"TEMPLATE"),URLQueryItem(name:"text",value:title),URLQueryItem(name:"dates",value:dates.0+"/"+dates.1),URLQueryItem(name:"stz",value:timeZone.identifier),URLQueryItem(name:"etz",value:timeZone.identifier),URLQueryItem(name:"details",value:details)]
        url.percentEncodedQuery=url.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B")
        guard let result=url.url else{throw MeetingError("Could not prepare the Google Calendar link.")}
        // Very large notes do not reliably fit in a browser URL. Keep the draft so
        // the user can shorten it or export the same event as an .ics file.
        guard result.absoluteString.utf8.count<=8000 else{throw MeetingError("These details are too long for a calendar link. Shorten them or use Export .ics.")}
        return result
    }
    func ics(now:Date=Date()) throws -> Data {
        if let validation{throw MeetingError(validation)}
        let dates=dateRange
        let stamp=Self.formatter("yyyyMMdd'T'HHmmss'Z'",timeZone:TimeZone(secondsFromGMT:0)!).string(from:now)
        let suffix=allDay ? ";VALUE=DATE":""
        let lines=["BEGIN:VCALENDAR","VERSION:2.0","PRODID:-//Meeting Notes//Calendar Export//EN","CALSCALE:GREGORIAN","BEGIN:VEVENT","UID:\(id)@meetingnotes.local","DTSTAMP:\(stamp)","DTSTART\(suffix):\(dates.0)","DTEND\(suffix):\(dates.1)","SUMMARY:\(Self.escape(title))","DESCRIPTION:\(Self.escape(details))","END:VEVENT","END:VCALENDAR"]
        return Data((lines.map(Self.fold).joined(separator:"\r\n")+"\r\n").utf8)
    }
    private static func escape(_ value:String)->String {
        value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n").replacingOccurrences(of:"\n",with:"\\n").replacingOccurrences(of:";",with:"\\;").replacingOccurrences(of:",",with:"\\,")
    }
    private static func fold(_ line:String)->String {
        var result="",bytes=0
        for scalar in line.unicodeScalars {
            let next=String(scalar),count=next.utf8.count
            if bytes+count>75{result+="\r\n ";bytes=1}
            result+=next;bytes+=count
        }
        return result
    }
    private static func formatter(_ pattern:String,timeZone:TimeZone)->DateFormatter {
        let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.calendar=Calendar(identifier:.gregorian);f.timeZone=timeZone;f.dateFormat=pattern;f.isLenient=false;return f
    }
}

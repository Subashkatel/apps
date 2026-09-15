import SwiftUI

struct TaskEditor:View {
    @ObservedObject var store:MeetingStore
    @State var task:WorkTask
    @Environment(\.dismiss) private var dismiss
    @State private var failure:String?
    private var hasDate:Binding<Bool>{Binding(get:{task.due != nil},set:{if $0{task.due=Self.dateString(Date())}else{task.due=nil;task.dueTime=nil}})}
    private var hasTime:Binding<Bool>{Binding(get:{task.dueTime != nil},set:{task.dueTime=$0 ? "17:00":nil})}
    static func dateString(_ date:Date)->String{formatter("yyyy-MM-dd").string(from:date)}
    static func formatter(_ format:String)->DateFormatter{let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat=format;return f}
    var body:some View {
        VStack(alignment:.leading,spacing:20){
            Text(store.tasks.contains{$0.id==task.id} ? "Edit task":"New task").font(.custom("Georgia",size:25))
            TextField("What needs to happen?",text:$task.title,axis:.vertical).font(.system(size:17)).lineLimit(1...4)
            Form{
                TextField("Owner",text:$task.owner,prompt:Text("Optional"))
                Picker("Project",selection:Binding(get:{task.projectID ?? ""},set:{task.projectID=$0.isEmpty ? nil:$0})){Text("Unfiled").tag("");ForEach(store.projects){Text($0.name).tag($0.id)}}
                Toggle("Due date",isOn:hasDate)
                if task.due != nil {
                    DatePicker("Date",selection:Binding(get:{Self.formatter("yyyy-MM-dd").date(from:task.due ?? "") ?? Date()},set:{task.due=Self.dateString($0)}),displayedComponents:.date)
                    Toggle("Specific time",isOn:hasTime)
                    if task.dueTime != nil {DatePicker("Time",selection:Binding(get:{Self.formatter("HH:mm").date(from:task.dueTime ?? "") ?? Date()},set:{task.dueTime=Self.formatter("HH:mm").string(from:$0)}),displayedComponents:.hourAndMinute)}
                }
            }
            if let id=task.meetingID,let m=store.meetings.first(where:{$0.id==id}){Text("From “\(m.title)”"+(m.deletedAt != nil ? " · in Trash":"")).font(.caption).foregroundStyle(Palette.secondary)}
            if let created=task.createdAt{Text("Added "+created.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(Palette.secondary)}
            if !task.history.isEmpty {DisclosureGroup("Task history"){ScrollView{Text(task.history.joined(separator:"\n")).font(.caption).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:110)}}
            if let failure{Text(failure).foregroundStyle(.orange)}
            HStack{Button("Cancel"){dismiss()}.keyboardShortcut(.cancelAction);if store.tasks.contains(where:{$0.id==task.id}){Button("Delete task",role:.destructive){if store.deleteTask(task.id){dismiss()}}};Spacer();Button("Save task"){if store.saveTask(task){dismiss()}else{failure=store.error;store.error=nil}}.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(task.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
        }.padding(28).frame(width:440).background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
    }
}
struct TaskRow:View {
    @ObservedObject var store:MeetingStore
    let task:WorkTask
    @State private var editing=false
    var body:some View{
        HStack(alignment:.top,spacing:10){
            Toggle("Complete task",isOn:Binding(get:{task.done},set:{_ in store.toggleTask(task.id)})).labelsHidden().toggleStyle(.checkbox)
            VStack(alignment:.leading,spacing:5){
                Button{editing=true}label:{Text(task.title).strikethrough(task.done).multilineTextAlignment(.leading).foregroundStyle(task.done ? Palette.secondary:Palette.ink)}.buttonStyle(.plain).help("Edit task")
                Text([task.owner.isEmpty ? nil:task.owner,task.due.map{"Due "+$0+(task.dueTime.map{" · "+$0} ?? "")},store.projects.first{$0.id==task.projectID}?.name].compactMap{$0}.joined(separator:" · ")).font(.caption).foregroundStyle(Palette.secondary)
                if let id=task.meetingID,store.meetings.contains(where:{$0.id==id && $0.deletedAt != nil}){Text("Source meeting in Trash").font(.caption).foregroundStyle(Palette.secondary)}
            }
            Spacer()
            Menu{Button("Edit task…"){editing=true};if let id=task.meetingID {
                if store.meetings.contains(where:{$0.id==id && $0.deletedAt==nil}){Button("Open source meeting"){store.select(id)}}else{Text("Source meeting is in Trash")}
            };Divider();Button("Delete task",role:.destructive){store.deleteTask(task.id)}}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width:32)
        }.sheet(isPresented:$editing){TaskEditor(store:store,task:task)}
    }
}

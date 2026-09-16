import SwiftUI
import AppKit
import LocalSupport

private func adaptive(_ dark: UInt32,_ light: UInt32)->Color {
    Color(nsColor:NSColor(name:nil){appearance in
        let hex=appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)
    })
}
enum Palette {
    static let background=adaptive(0x22251f,0xf7f5ed)
    static let panel=adaptive(0x2b3027,0xeaece2)
    static let ink=adaptive(0xedeedf,0x293025)
    static let secondary=adaptive(0xabb2a3,0x626c59)
    static let accent=adaptive(0xc7d6b3,0x4c633c)
}
struct MeetingRoot: View {
    @ObservedObject var store: MeetingStore
    @ObservedObject var discussion: DiscussionStore
    init(store:MeetingStore){self.store=store;self.discussion=store.discussion}
    @State private var projectName=""
    @State private var addingProject=false
    @State private var showTrash=false
    @State private var calendarDraft:CalendarDraft?
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                Button {store.sidebar.toggle()} label:{Image(systemName:"sidebar.left")}.help("Show or hide the meeting list")
                Image(nsImage:NSApp.applicationIconImage).resizable().frame(width:24,height:24).accessibilityHidden(true)
                Text("Meeting Notes").fontWeight(.medium)
                Spacer()
                if store.starting {ProgressView().controlSize(.small)}
                if store.isRecording {Button("Stop recording"){store.stopRecording()}.foregroundStyle(.orange)}
                Menu {
                    Button("Start recording",action:{Task{await store.beginRecording()}}).disabled(store.isRecording || store.starting)
                    Button("Stop recording"){store.stopRecording()}.disabled(!store.isRecording)
                    Divider()
                    Button("\(store.preferences.mode == .microphone ? "✓ " : "")In person · microphone") {setMode(.microphone)}
                    Button("\(store.preferences.mode == .call ? "✓ " : "")Online · microphone + system") {setMode(.call)}
                    if store.isRecording {Text("Mode changes apply to the next recording")}
                    Divider()
                    Button("Settings…"){store.settingsOpen=true}
                    Button("Open data folder"){NSWorkspace.shared.open(store.database.root)}
                    Button("Recently deleted…"){showTrash=true}
                    Button("Hide window"){NSApp.keyWindow?.orderOut(nil);NSApp.setActivationPolicy(.accessory)}
                } label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width:30).help("Recording options and settings")
            }.buttonStyle(.plain).padding(.horizontal,20).padding(.vertical,14)
            Divider()
            HStack(spacing:0) {
                if store.sidebar {sidebar.frame(width:220);Divider()}
                if store.current==nil && store.currentProject==nil && store.selection != "tasks" && !discussion.isOpen {empty.frame(maxWidth:.infinity,maxHeight:.infinity)}
                else {DiscussionWorkspace(store:store,discussion:discussion)}
            }
            if store.unsavedCount>0 {
                HStack{Text("Some edits are not saved.").foregroundStyle(.orange);Button("Retry saving"){store.flush()};Spacer()}.padding(12)
            }
            if !store.status.isEmpty {Text(store.status).font(.caption).foregroundStyle(Palette.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,20).padding(.vertical,6)}
        }.background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
        .preferredColorScheme(store.preferences.appearance == "light" ? .light:.dark)
        .frame(minWidth:discussion.isOpen && store.sidebar ? 1020:780,minHeight:560)
        .sheet(isPresented:$store.settingsOpen){MeetingSettings(store:store)}
        .sheet(isPresented:Binding(get:{store.pendingSummaryID != nil},set:{if !$0{store.pendingSummaryID=nil}})) {
            if let id=store.pendingSummaryID { SummaryProjectChoice(store:store,meetingID:id) }
        }
        .sheet(isPresented:$showTrash){TrashView(store:store)}
        .sheet(item:$calendarDraft){CalendarSheet(draft:$0,store:store)}
        .confirmationDialog("Move meeting to Trash?",isPresented:Binding(get:{store.pendingDeleteMeeting != nil},set:{if !$0{store.pendingDeleteMeeting=nil}}),titleVisibility:.visible){
            if let id=store.pendingDeleteMeeting {
                let count=store.meetingTasks(id).count
                if count>0 {
                    Button("Delete meeting and \(count) \(count == 1 ? "task":"tasks")",role:.destructive){store.delete(id,includingTasks:true);store.pendingDeleteMeeting=nil}
                    Button("Delete meeting only — keep tasks",role:.destructive){store.delete(id);store.pendingDeleteMeeting=nil}
                }else{Button("Move to Trash",role:.destructive){store.delete(id);store.pendingDeleteMeeting=nil}}
                Button("Cancel",role:.cancel){store.pendingDeleteMeeting=nil}
            }
        } message:{Text("Audio, notes and deleted tasks stay recoverable in Recently deleted. Tasks kept separately cannot open a trashed meeting.")}
        .alert("Meeting Notes",isPresented:Binding(get:{store.error != nil},set:{if !$0{store.error=nil}})){Button("OK"){store.error=nil}} message:{Text(store.error ?? "")}
        .alert("New project",isPresented:$addingProject){TextField("Project name",text:$projectName);Button("Create"){store.addProject(projectName);projectName=""};Button("Cancel",role:.cancel){}} message:{Text("Keep tasks and open questions together across meetings.")}
    }
    private func setMode(_ mode: CaptureMode){var p=store.preferences;p.mode=mode;store.savePreferences(p);store.status=(store.isRecording ? "Next recording: " : "Mode: ")+mode.title}
    private var sidebar: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:6){
                Button{store.select("tasks")}label:{Label("Tasks",systemImage:"checklist").font(.system(size:13,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading).padding(10).background(store.selection == "tasks" ? Palette.panel:Color.clear).clipShape(RoundedRectangle(cornerRadius:6))}.buttonStyle(.plain)
                Text("Meetings").font(.caption).foregroundStyle(Palette.secondary).padding(.horizontal,10).padding(.bottom,6)
                ForEach(store.meetings.filter{$0.deletedAt==nil}){m in
                    Button{store.select(m.id)} label:{VStack(alignment:.leading,spacing:4){Text(m.title).font(.system(size:13,weight:.medium)).lineLimit(2);Text(m.draft?.applied == true ? m.created.formatted(date:.abbreviated,time:.omitted) : m.phase.title).font(.caption).foregroundStyle(Palette.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(store.selection==m.id ? Palette.panel:Color.clear).clipShape(RoundedRectangle(cornerRadius:6))}.buttonStyle(.plain)
                    .contextMenu{Button("Add to calendar…"){calendarDraft=CalendarDraft.meeting(m,project:store.projects.first{$0.id==m.projectID}?.name)};Divider();Button("Export note & transcript…"){store.export(m)};Button("Show audio files"){store.reveal(m.id)};Button("Move to Trash…",role:.destructive){store.pendingDeleteMeeting=m.id}}
                }
                HStack{Text("Projects").font(.caption).foregroundStyle(Palette.secondary);Spacer();Button{addingProject=true}label:{Image(systemName:"plus")}.buttonStyle(.plain).help("Add project")}.padding(.horizontal,10).padding(.top,26)
                ForEach(store.projects){p in Button{store.select("project:"+p.id)}label:{Text(p.name).font(.system(size:13,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading).padding(10).background(store.selection == "project:"+p.id ? Palette.panel:Color.clear).clipShape(RoundedRectangle(cornerRadius:6))}.buttonStyle(.plain)}
            }.padding(12)
        }
    }
    private var empty: some View {
        VStack(alignment:.leading,spacing:18){Text("A place for the conversation.").font(.custom("Georgia",size:28));Text("Click the bear in the menu bar to record. Your audio and notes will collect here.").foregroundStyle(Palette.secondary).frame(maxWidth:410,alignment:.leading)
            Picker("Record",selection:Binding(get:{store.preferences.mode},set:{setMode($0)})){ForEach(CaptureMode.allCases){Text($0.title).tag($0)}}.frame(maxWidth:360)
            Button("Start recording"){Task{await store.beginRecording()}}.buttonStyle(.borderedProminent).disabled(store.starting)
            Button("AI & transcription settings…"){store.settingsOpen=true}.buttonStyle(.plain).foregroundStyle(Palette.secondary)
        }.padding(40)
    }
}
struct MeetingDocument: View {
    @ObservedObject var store: MeetingStore
    let id: String
    @State private var calendarDraft:CalendarDraft?
    @State private var reviewTasks=false
    @State private var originals=false
    @State private var confirmRegenerate=false
    @State private var addingTask=false
    @State private var addingProject=false
    @State private var projectName=""
    @State private var showDecision=false
    @State private var showQuestion=false
    @State private var showTopics=false
    private var meeting: Meeting?{store.meetings.first{$0.id==id}}
    private func text(_ key:WritableKeyPath<Meeting,String>)->Binding<String>{Binding(get:{meeting?[keyPath:key] ?? ""},set:{value in store.update(id){$0[keyPath:key]=value}})}
    private func draftText(_ key:WritableKeyPath<MeetingDraft,String>)->Binding<String>{Binding(get:{meeting?.draft?[keyPath:key] ?? ""},set:{value in store.update(id){$0.draft?[keyPath:key]=value}})}
    var body: some View {
        HStack(spacing:0) {
            ScrollView {
                if let m=meeting {
                    VStack(alignment:.leading,spacing:22) {
                        title(m)
                        if let problem=m.error {
                            VStack(alignment:.leading,spacing:8){
                                Text(problem).foregroundStyle(.orange).font(.callout).textSelection(.enabled)
                                HStack{
                                    Button("AI & transcription settings…"){store.settingsOpen=true}
                                    if store.activeID != id,store.transcriptionProgress[id] == nil,!store.drafting.contains(id){
                                        if m.transcript.isEmpty || m.phase == .failed || m.phase == .interrupted{Button("Retry transcription"){store.transcribe(id)}}
                                        if !m.transcript.isEmpty{Button("Retry summary"){Task{await store.summarize(id)}}}
                                    }
                                }.font(.caption).buttonStyle(.plain).foregroundStyle(Palette.accent)
                            }
                        }
                        if store.activeID==id {live(m)}
                        else if let progress=store.transcriptionProgress[id] {HStack{ProgressView().controlSize(.small);Text(progress).foregroundStyle(Palette.secondary)};roughNotes;audioActions(m)}
                        else if let draft=m.draft {draftView(m,draft)}
                        else {ready(m)}
                        AttachmentList(store:store,meeting:m)
                        Divider()
                        HStack{Text("Tasks").fontWeight(.medium);Spacer();Button("Add task"){addingTask=true}.buttonStyle(.plain).foregroundStyle(Palette.accent)}
                        ForEach(store.tasks.filter{$0.deletedAt==nil && ($0.meetingID==id || (m.draft?.appliedTaskIDs.contains($0.id) ?? false))}){task in TaskRow(store:store,task:task)}
                    }.padding(32).frame(maxWidth:780,alignment:.leading).frame(maxWidth:.infinity,alignment:.topLeading)
                }
            }
            if store.transcriptOpen,let m=meeting {Divider();TranscriptPanel(store:store,meeting:m).frame(minWidth:260,idealWidth:330,maxWidth:400)}
        }
        .sheet(item:$calendarDraft){CalendarSheet(draft:$0,store:store)}
        .sheet(isPresented:$addingTask){TaskEditor(store:store,task:WorkTask(projectID:meeting?.projectID,title:"",owner:"Me",meetingID:id))}
        .alert("New project",isPresented:$addingProject){TextField("Project name",text:$projectName);Button("Create"){store.addProject(projectName);if let p=store.projects.first(where:{$0.name.caseInsensitiveCompare(projectName.trimmingCharacters(in:.whitespacesAndNewlines)) == .orderedSame}){store.assignProject(id,project:p.id);store.select(id)};projectName=""};Button("Cancel",role:.cancel){}}
        .confirmationDialog("Replace the AI draft? Your original notes and audio are kept.",isPresented:$confirmRegenerate){Button("Generate a new draft"){Task{await store.summarize(id)}}}
    }
    private func title(_ m:Meeting)->some View {
        VStack(alignment:.leading,spacing:10){
            TextField("Meeting title",text:Binding(get:{meeting?.title ?? ""},set:{value in store.update(id){$0.title=value;$0.titleEdited=true}}),axis:.vertical).font(.custom("Georgia",size:29)).textFieldStyle(.plain).lineLimit(1...4).fixedSize(horizontal:false,vertical:true)
            Text(m.created.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal:false,vertical:true)
            HStack(spacing:10){
                HStack(spacing:8){
                    Text("Project").font(.caption).foregroundStyle(Palette.secondary)
                    Menu {
                        Button("Standalone"){store.assignProject(id,project:nil)}
                        ForEach(store.projects){p in Button(p.name){store.assignProject(id,project:p.id)}}
                        Divider();Button("New project…"){addingProject=true}
                    } label:{HStack(spacing:8){Text(store.projects.first{$0.id==m.projectID}?.name ?? "Standalone").lineLimit(1);Image(systemName:"chevron.down").font(.system(size:9))}.foregroundStyle(Palette.ink).padding(.horizontal,10).padding(.vertical,6).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:5))}
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal:false,vertical:true).disabled(store.drafting.contains(id))
                }.frame(maxWidth:280,alignment:.leading)
                Spacer()
                DiscussButton(store:store,discussion:store.discussion,meeting:m)
                Menu{Button("Add to calendar…"){calendarDraft=CalendarDraft.meeting(m,project:store.projects.first{$0.id==m.projectID}?.name)};Divider();Button("Export note & transcript…"){store.export(m)};Button("Show audio files"){store.reveal(id)};Button("Move to Trash…",role:.destructive){store.pendingDeleteMeeting=id}.disabled(store.activeID==id || store.transcriptionProgress[id] != nil || store.drafting.contains(id))}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width:32)
            }
        }
    }
    private var roughNotes: some View {
        VStack(alignment:.leading,spacing:8){Text("My notes").font(.caption).foregroundStyle(Palette.secondary);FormattedNotes(text:text(\.notes))}
    }
    private func live(_ m:Meeting)->some View {
        VStack(alignment:.leading,spacing:20){TimelineView(.periodic(from:.now,by:1)){_ in HStack{Circle().fill(.orange).frame(width:6,height:6);Text("Recording · "+Segment.timestamp(m.duration));Spacer();Button("Stop"){store.stopRecording()}}.font(.callout)};Text(m.mode.title).font(.caption).foregroundStyle(Palette.secondary);roughNotes;Text("Notes save as you type. You can hide this window while recording.").font(.caption).foregroundStyle(Palette.secondary)}
    }
    private func audioActions(_ m:Meeting)->some View {
        VStack(alignment:.leading,spacing:10){
            HStack(spacing:16){
                Button("Listen to microphone"){store.play(m)}.disabled(!FileManager.default.fileExists(atPath:store.database.folder(id).appendingPathComponent("mic.caf").path))
                if m.mode == .call {Button("Listen to call audio"){store.play(m,track:"system")}}
                if !m.transcript.isEmpty {Button("Transcript ↗"){store.transcriptOpen.toggle()}}
            }.font(.caption).buttonStyle(.plain).foregroundStyle(Palette.accent)
            if store.playingID==id {PlaybackControls(playback:store.playback)}
        }
    }
    private func ready(_ m:Meeting)->some View {
        VStack(alignment:.leading,spacing:22){
            Text(m.phase.title).font(.caption).foregroundStyle(Palette.secondary)
            audioActions(m)
            roughNotes
            projectContext(m)
            Divider()
            HStack(alignment:.top){VStack(alignment:.leading,spacing:9){
                if m.transcript.isEmpty {Button("Transcribe recording"){store.transcribe(id)}.buttonStyle(.borderedProminent)}
                else {Button(store.drafting.contains(id) ? "Summarizing…" : "Summarize & find tasks"){Task{await store.summarize(id)}}.buttonStyle(.borderedProminent).disabled(store.drafting.contains(id))}
                Button("AI settings · "+store.preferences.ai.selectionLabel+" ⌄"){store.settingsOpen=true}.font(.caption).buttonStyle(.plain).foregroundStyle(Palette.secondary)
                if let progress=store.summaryProgress[id]{Text(progress).font(.caption).foregroundStyle(Palette.secondary)}
            };Spacer();if store.drafting.contains(id){ProgressView().controlSize(.small)}else{Text("Your original notes are kept.").font(.caption).foregroundStyle(Palette.secondary)}}
        }
    }
    private func projectContext(_ m:Meeting)->some View {
        let context=ProjectContext.make(for:m,from:store.meetings)
        let ids=m.draft?.contextMeetingIDs ?? context.entries.map(\.id)
        let omitted=m.draft?.omittedContextCount ?? context.omitted
        return Group {
            if m.projectID != nil {
                DisclosureGroup(m.draft?.contextMeetingIDs == nil ? "Project context for next summary · \(context.entries.count) meetings":"Project context used · \(ids.count) meetings") {
                    VStack(alignment:.leading,spacing:8){
                        Text("Project notes, saved summaries, decisions, open questions, personal notes and current open tasks. Earlier full transcripts and attachment contents are not included.")
                        if omitted>0{Text("\(omitted) meetings exceed the context limit and are excluded. Recent meetings take priority.").foregroundStyle(.orange)}
                        ForEach(ids,id:\.self){id in if let previous=store.meetings.first(where:{$0.id==id}){Button(previous.title+(previous.deletedAt != nil ? " · in Trash":"")){store.select(id)}.buttonStyle(.plain).disabled(previous.deletedAt != nil)}}
                    }.padding(.top,8)
                }.font(.caption).foregroundStyle(Palette.secondary)
            }
        }
    }
    private func draftView(_ m:Meeting,_ d:MeetingDraft)->some View {
        VStack(alignment:.leading,spacing:22){
            HStack{Button("\(d.applied ? "Saved" : "Draft") · \(d.provider) · \(d.model) ⌄"){store.settingsOpen=true}.font(.caption).buttonStyle(.plain).foregroundStyle(Palette.secondary);Spacer();Button("Transcript ↗"){store.transcriptOpen.toggle()}.font(.caption).buttonStyle(.plain)}
            projectContext(m)
            if let progress=store.summaryProgress[id]{Text(progress).font(.caption).foregroundStyle(Palette.secondary)}
            if !(d.topics ?? "").isEmpty || showTopics {
                DiscussionSummary(text:Binding(get:{meeting?.draft?.topics ?? ""},set:{value in store.update(id){$0.draft?.topics=value}}))
            }
            if let issues=d.reviewIssues,!issues.isEmpty {ForEach(issues,id:\.self){Text($0).font(.caption).foregroundStyle(Palette.secondary)}}
            if let deferred=d.deferredTasks,!deferred.isEmpty {
                DisclosureGroup("\(deferred.count) \(deferred.count == 1 ? "task suggestion needs" : "task suggestions need") checking") {
                    VStack(alignment:.leading,spacing:12) {
                        Text("Your summary is kept. These suggestions will not change any tasks.").font(.caption).foregroundStyle(Palette.secondary)
                        ForEach(Array(deferred.enumerated()),id:\.offset){_,item in
                            VStack(alignment:.leading,spacing:4){
                                Text(item.title).textSelection(.enabled)
                                Text(item.reason).font(.caption).foregroundStyle(Palette.secondary)
                                if let suggestion=try? JSONDecoder().decode(DraftResponse.Change.self,from:Data(item.response.utf8)) {
                                    Text([suggestion.owner,suggestion.due,suggestion.dueTime].compactMap{$0}.filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(Palette.secondary)
                                    if let source=suggestion.evidence.first(where:{evidence in m.transcript.contains{$0.id==evidence}}){Button("View source passage"){store.sourceSegment=source;store.transcriptOpen=true}.font(.caption).buttonStyle(.plain).foregroundStyle(Palette.accent)}
                                }
                            }
                        }
                        HStack{Button("View transcript"){store.transcriptOpen=true};Button("Add task manually"){addingTask=true}}.buttonStyle(.plain).foregroundStyle(Palette.accent)
                    }.padding(.top,8)
                }
            }
            EditablePassage(title:"Detailed summary",text:draftText(\.summary),height:100)
            if !d.decision.isEmpty || showDecision {EditablePassage(title:"Decided",text:draftText(\.decision),height:65).help("Agreements and conclusions reached in this meeting")}
            if !d.question.isEmpty || showQuestion {EditablePassage(title:"Still open",text:draftText(\.question),height:65).help("Unresolved questions to return to")}
            if (d.topics ?? "").isEmpty || d.decision.isEmpty || d.question.isEmpty {Menu("Add section"){if (d.topics ?? "").isEmpty{Button("What we talked about"){showTopics=true}};if d.decision.isEmpty{Button("Decided"){showDecision=true}};if d.question.isEmpty{Button("Still open"){showQuestion=true}}}.menuStyle(.borderlessButton).fixedSize().font(.caption)}
            if !d.evidence.isEmpty {Button("Check source passages ↗"){store.sourceSegment=d.evidence.first;store.transcriptOpen=true}.font(.caption).buttonStyle(.plain)}
            if !d.applied,!d.changes.isEmpty {
                Divider()
                DisclosureGroup(isExpanded:$reviewTasks){VStack(alignment:.leading,spacing:18){ForEach(d.changes){change in TaskProposal(store:store,meetingID:id,change:change)}}.padding(.top,12)} label:{Text("\(d.changes.count) suggested tasks · review before saving").fontWeight(.medium)}
            }
            if d.changes.isEmpty,d.appliedTaskIDs.isEmpty {
                HStack{Text("No task suggestions saved.").font(.caption).foregroundStyle(Palette.secondary);Button("Find tasks"){Task{await store.findTasks(id)}}.disabled(store.drafting.contains(id))}
            }
            if let related=d.relatedMeetingID,let previous=store.meetings.first(where:{$0.id==related && $0.deletedAt==nil}) {DisclosureGroup("Continues “\(previous.title)”"){VStack(alignment:.leading,spacing:10){Text(d.relatedReason ?? "");Button("Open earlier meeting"){store.select(related)}}.padding(.top,8)}.font(.caption).foregroundStyle(Palette.secondary)}
            DisclosureGroup("My notes",isExpanded:$originals){
                VStack(alignment:.leading,spacing:12){
                    FormattedNotes(text:text(\.notes))
                    if d.originalNotes != m.notes {
                        DisclosureGroup("Notes used for this draft") {Text(d.originalNotes.isEmpty ? "No notes were typed before summarizing.":d.originalNotes).textSelection(.enabled).padding(.top,8)}
                    }
                }.padding(.top,10)
            }.foregroundStyle(Palette.secondary).font(.caption)
            HStack{
                Button(!d.applied && !d.changes.isEmpty && !reviewTasks ? "Review task changes" : d.applied ? "Save edits" : "Save note & selected tasks"){
                    if !d.applied && !d.changes.isEmpty && !reviewTasks{reviewTasks=true}else{store.saveDraft(id)}
                }.buttonStyle(.borderedProminent)
                if store.drafting.contains(id){ProgressView().controlSize(.small)}else{Menu{Button("Generate a new draft…"){confirmRegenerate=true};Button("Retry transcription"){store.transcribe(id)}}label:{Text("More")}.menuStyle(.borderlessButton).fixedSize()}
            }.disabled(store.drafting.contains(id))
            audioActions(m)
        }
    }
}
struct DiscussionSummary: View {
    @Binding var text:String
    @AppStorage("meetingDiscussionExpanded") private var expanded=true
    @State private var editing=false
    var body:some View {
        DisclosureGroup(isExpanded:$expanded){
            VStack(alignment:.leading,spacing:10){
                if editing {NoteEditor(text:$text,minimumHeight:60,label:"What we talked about")}
                else {MarkdownNotes(text:text).frame(maxWidth:.infinity,alignment:.leading)}
                HStack{Spacer();Button(editing ? "Done editing":"Edit"){editing.toggle()}.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.secondary).accessibilityLabel(editing ? "Finish editing discussion":"Edit what we talked about")}
            }.padding(.top,10)
        } label:{Text("What we talked about").font(.system(size:13,weight:.medium))}
        .tint(Palette.secondary)
    }
}
struct EditablePassage: View {
    let title:String?
    @Binding var text:String
    let height:CGFloat
    var body:some View {VStack(alignment:.leading,spacing:7){if let title{Text(title).font(.system(size:13,weight:.medium))};NoteEditor(text:$text,minimumHeight:28,label:title ?? "Meeting summary")}}
}
struct TaskProposal: View {
    @ObservedObject var store:MeetingStore
    let meetingID:String
    let change:TaskChange
    private func binding<T>(_ key:WritableKeyPath<TaskChange,T>)->Binding<T>{Binding(get:{store.meetings.first{$0.id==meetingID}?.draft?.changes.first{$0.id==change.id}?[keyPath:key] ?? change[keyPath:key]},set:{value in store.update(meetingID){m in if let i=m.draft?.changes.firstIndex(where:{$0.id==change.id}){m.draft?.changes[i][keyPath:key]=value}}})}
    var body:some View {
        HStack(alignment:.top,spacing:10){Toggle("Accept task",isOn:binding(\.accepted)).labelsHidden().toggleStyle(.checkbox);VStack(alignment:.leading,spacing:7){Text(change.existingID == nil ? "New task":"Update existing task").font(.caption).foregroundStyle(Palette.accent);TextField("Next action",text:binding(\.title),axis:.vertical).textFieldStyle(.plain)
            if let id=change.existingID,let task=store.tasks.first(where:{$0.id==id}){Text("Was: "+task.title).font(.caption).foregroundStyle(Palette.secondary)}
            DisclosureGroup("\(change.owner.isEmpty ? "Owner not set":change.owner) · \(change.due ?? "No date agreed") · Edit"){
                VStack(alignment:.leading,spacing:10){TextField("Owner",text:binding(\.owner));TextField("Due date · YYYY-MM-DD",text:Binding(get:{binding(\.due).wrappedValue ?? ""},set:{binding(\.due).wrappedValue=$0.isEmpty ? nil:$0}));TextField("Due time · HH:mm (optional)",text:Binding(get:{binding(\.dueTime).wrappedValue ?? ""},set:{binding(\.dueTime).wrappedValue=$0.isEmpty ? nil:$0}));Button("Show commitment in transcript"){store.sourceSegment=change.evidence.first;store.transcriptOpen=true}.buttonStyle(.plain)}.padding(.top,10)
            }.font(.caption).foregroundStyle(Palette.secondary)
        }}
    }
}
struct TranscriptPanel:View {
    @ObservedObject var store:MeetingStore
    let meeting:Meeting
    private var segments:[Segment]{store.sourceSegment == nil || store.transcriptUsesCurrentVersion ? meeting.transcript : meeting.draft?.sourceTranscript ?? meeting.transcript}
    var body:some View {VStack(alignment:.leading,spacing:12){HStack{Text("Transcript").fontWeight(.medium);Spacer();Button{store.transcriptOpen=false;store.sourceSegment=nil;store.transcriptUsesCurrentVersion=false}label:{Image(systemName:"xmark")}.buttonStyle(.plain).help("Close transcript")};Text("Audio tracks, not verified speakers. Click a timestamp to listen.").font(.caption).foregroundStyle(Palette.secondary)
        ScrollViewReader{proxy in ScrollView{LazyVStack(alignment:.leading,spacing:20){ForEach(segments){s in VStack(alignment:.leading,spacing:6){HStack{Button(s.time){store.play(meeting,segment:s)}.buttonStyle(.plain).foregroundStyle(Palette.accent);Text(s.speaker).foregroundStyle(Palette.secondary)}.font(.caption);Text(s.text).font(.system(size:13)).textSelection(.enabled)}.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(store.sourceSegment==s.id ? Palette.panel:Color.clear).id(s.id)}}.onAppear{if let id=store.sourceSegment{proxy.scrollTo(id,anchor:.center)}}.onChange(of:store.sourceSegment){_,id in if let id{proxy.scrollTo(id,anchor:.center)}}}
        }
        if store.playingID==meeting.id{Button("Stop playback"){store.stopPlayback()}}
    }.padding(20).background(Palette.background)}
}
struct ProjectDocument:View {
    @ObservedObject var store:MeetingStore
    let project:MeetingProject?
    @State private var addingTask=false
    @State private var query=TaskQuery()
    @State private var grouping="none"
    private var visible:[WorkTask]{var q=query;if let project{q.project=project.id};return q.results(store.tasks)}
    private func group(_ t:WorkTask)->String {
        if grouping=="project"{return store.projects.first{$0.id==t.projectID}?.name ?? "Unfiled"}
        if grouping=="meeting"{return store.meetings.first{$0.id==t.meetingID}?.title ?? "No meeting"}
        return t.due ?? "No due date"
    }
    var body:some View{ScrollView{VStack(alignment:.leading,spacing:22){
        HStack{Text(project?.name ?? "Tasks").font(.custom("Georgia",size:29));Spacer();Button("Add task"){addingTask=true}.buttonStyle(.borderedProminent)}
        if let project {ProjectNotesEditor(store:store,project:project)}
        TaskFilterBar(store:store,project:project,query:$query,grouping:$grouping,count:visible.count)
        if visible.isEmpty{Text("No tasks match these filters.").foregroundStyle(Palette.secondary).padding(.vertical,16)}
        if grouping=="none"{ForEach(visible){task in TaskRow(store:store,task:task);Divider()}}
        else {ForEach(Array(Set(visible.map{group($0)})).sorted(),id:\.self){key in
            Text(key).font(.system(size:13,weight:.medium)).foregroundStyle(Palette.secondary).padding(.top,8)
            ForEach(visible.filter{group($0)==key}){task in TaskRow(store:store,task:task);Divider()}
        }}
        if let project {
            if !project.question.isEmpty{Text("Still open").fontWeight(.medium);Text(project.question).font(.custom("Georgia",size:17)).textSelection(.enabled)}
            Text("Meetings").fontWeight(.medium)
            ForEach(store.meetings.filter{$0.projectID==project.id && $0.deletedAt==nil}){m in Button{store.select(m.id)}label:{VStack(alignment:.leading,spacing:5){Text(m.title);Text(m.created.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(Palette.secondary)}}.buttonStyle(.plain)}
        }
    }.padding(32).frame(maxWidth:900,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading)}.sheet(isPresented:$addingTask){TaskEditor(store:store,task:WorkTask(projectID:project?.id,title:"",owner:"Me"))}}

}
struct TrashView:View {
    @ObservedObject var store:MeetingStore
    @Environment(\.dismiss) private var dismiss
    var body:some View{
        VStack(alignment:.leading,spacing:20){
            HStack{Text("Recently deleted").font(.custom("Georgia",size:24));Spacer();Button("Done"){dismiss()}}
            Text("Restore a meeting to open it again. Tasks deleted with a meeting return when it is restored; independently deleted tasks stay here.").font(.callout).foregroundStyle(Palette.secondary)
            List {
                Section("Meetings") {ForEach(store.meetings.filter{$0.deletedAt != nil}){m in HStack{Text(m.title);Spacer();Button("Restore meeting"){store.restore(m.id)};Button("Show files"){store.reveal(m.id)}}}}
                Section("Tasks") {ForEach(store.tasks.filter{$0.deletedAt != nil}){t in HStack{VStack(alignment:.leading){Text(t.title);if t.deletedWithMeetingID != nil{Text("Deleted with its meeting").font(.caption).foregroundStyle(.secondary)}};Spacer();Button("Restore task"){store.restoreTask(t.id)}}}}
            }
        }.padding(24).frame(width:640,height:440).background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
    }
}

struct SummaryProjectChoice:View {
    @ObservedObject var store:MeetingStore
    let meetingID:String
    @State private var choice="standalone"
    @State private var name=""
    @State private var problem:String?
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            Text("Where does this meeting belong?").font(.custom("Georgia",size:25))
            Text("Keep it standalone, or use a project's notes, earlier meetings and open tasks as context. You can change this later.").font(.callout).foregroundStyle(Palette.secondary)
            Picker("Save in",selection:$choice){Text("Standalone meeting").tag("standalone");ForEach(store.projects){Text($0.name).tag($0.id)};Text("New project…").tag("new")}
            if choice=="new"{TextField("Project name",text:$name).textFieldStyle(.roundedBorder)}
            if let problem{Text(problem).foregroundStyle(.orange).font(.caption)}
            HStack{Button("Cancel"){store.pendingSummaryID=nil}.keyboardShortcut(.cancelAction);Spacer();Button("Continue to summary"){
                var project:String?=choice=="standalone" ? nil:choice
                if choice=="new" {
                    let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
                    guard !trimmed.isEmpty else{return}
                    if store.projects.contains(where:{$0.name.caseInsensitiveCompare(trimmed) == .orderedSame}){problem="This project already exists. Choose it from the list.";return}
                    store.addProject(trimmed)
                    guard let created=store.projects.first(where:{$0.name==trimmed}) else{problem="The project could not be saved.";return}
                    project=created.id
                }
                store.assignProject(meetingID,project:project)
                guard let meeting=store.meetings.first(where:{$0.id==meetingID}),!store.needsProjectChoice(meeting),meeting.projectID==project else{problem="Your choice could not be saved. Please try again.";return}
                store.pendingSummaryID=nil;store.select(meetingID)
                let taskRecovery=store.pendingTaskRecovery;store.pendingTaskRecovery=false
                Task{if taskRecovery{await store.findTasks(meetingID)}else{await store.summarize(meetingID)}}
            }.buttonStyle(.borderedProminent).disabled(choice=="new" && name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)}
        }.padding(28).frame(width:480).background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
    }
}
struct ProjectNotesEditor:View {
    @ObservedObject var store:MeetingStore
    let project:MeetingProject
    @State private var editing=false
    @State private var text=""
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            HStack{Text("Project notes").fontWeight(.medium);Spacer();if !editing{Button((project.notes ?? "").isEmpty ? "Add notes":"Edit"){text=project.notes ?? "";editing=true}.buttonStyle(.plain).foregroundStyle(Palette.accent)}}
            if editing{
                FormattedNotes(text:$text)
                HStack{Text("Background for future summaries, not new task evidence.").font(.caption).foregroundStyle(Palette.secondary);Spacer();Button("Cancel"){editing=false};Button("Save notes"){if store.saveProjectNotes(project.id,notes:text){editing=false}}.buttonStyle(.borderedProminent)}
            }else if let notes=project.notes,!notes.isEmpty{Text(.init(notes)).textSelection(.enabled)}
            else{Text("What is this project about? Add its purpose, goals and useful context.").font(.callout).foregroundStyle(Palette.secondary)}
            Divider()
        }
    }
}

import SwiftUI
import AppKit
import LocalSupport

struct DiscussionWorkspace:View {
    @ObservedObject var store:MeetingStore
    @ObservedObject var discussion:DiscussionStore
    var body:some View {
        HStack(spacing:0) {
            if discussion.isOpen,store.transcriptOpen,let meeting=store.current {
                TranscriptPanel(store:store,meeting:meeting).frame(maxWidth:.infinity)
            } else if let m=store.current {MeetingDocument(store:store,id:m.id).id(m.id)}
            else if let p=store.currentProject {ProjectDocument(store:store,project:p).id(p.id)}
            else if store.selection == "tasks" {ProjectDocument(store:store,project:nil)}
            else {Text("Choose a meeting to read your notes.").foregroundStyle(Palette.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)}
            if discussion.isOpen {Divider();DiscussionPanel(store:store,discussion:discussion).frame(width:350)}
        }
    }
}
struct DiscussButton:View {
    @ObservedObject var store:MeetingStore
    @ObservedObject var discussion:DiscussionStore
    let meeting:Meeting
    var body:some View {
        Button {if discussion.isOpen && discussion.current?.meetingID==meeting.id{discussion.close()}else{discussion.open(meeting:meeting,settings:store.preferences.ai)}} label:{Label("Discuss",systemImage:"bubble.left.and.bubble.right")}
        .buttonStyle(.plain).foregroundStyle(Palette.accent).help("Open or close a discussion alongside this meeting").accessibilityIdentifier("discussion.toggle")
    }
}
struct DiscussionPanel:View {
    @ObservedObject var store:MeetingStore
    @ObservedObject var discussion:DiscussionStore
    @State private var modelOpen=false
    @State private var contextOpen=false
    @State private var historyOpen=false
    @State private var source:DiscussionSource?
    @State private var saving:DiscussionMessage?
    private var thread:DiscussionThread?{discussion.current}
    private var active:Bool{thread.map{discussion.running.contains($0.id)} ?? false}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text("Discuss").font(.custom("Georgia",size:21));Spacer()
                Button{historyOpen=true}label:{Image(systemName:"clock.arrow.circlepath")}.help("Discussion history").accessibilityLabel("Discussion history")
                Button{if let t=thread,let m=store.meetings.first(where:{$0.id==t.meetingID}){discussion.new(meeting:m,settings:t.settings(store.preferences.ai),scope:t.scope);if let id=discussion.selectedID{discussion.change(id){$0.effort=t.effort}}}}label:{Image(systemName:"square.and.pencil")}.help("New discussion").accessibilityLabel("New discussion")
                Button{discussion.close()}label:{Image(systemName:"xmark")}.help("Close discussion").accessibilityLabel("Close discussion")
            }.buttonStyle(.plain).padding(18)
            if let thread {
                VStack(alignment:.leading,spacing:8){
                    Text(store.meetings.first{$0.id==thread.meetingID}?.title ?? "Meeting unavailable").font(.caption).lineLimit(2).foregroundStyle(Palette.secondary)
                    Button{modelOpen=true}label:{HStack{Text(thread.label).multilineTextAlignment(.leading);Image(systemName:"chevron.down")}}.accessibilityLabel("Discussion model and reasoning effort")
                    Button{contextOpen=true}label:{Label(thread.scope.title,systemImage:"doc.text.magnifyingglass")}.accessibilityLabel("Discussion context: "+thread.scope.title)
                }.font(.caption).buttonStyle(.plain).foregroundStyle(Palette.accent).padding(.horizontal,18).padding(.bottom,14)
                Divider()
                ScrollViewReader {proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:22) {
                            if thread.messages.isEmpty {
                                VStack(alignment:.leading,spacing:10){Text("Think it through").font(.custom("Georgia",size:23));Text("Ask about the meeting, test an idea, or get a second perspective. Your notes stay yours.").font(.callout).foregroundStyle(Palette.secondary)}.padding(.vertical,24)
                            }
                            ForEach(thread.messages){message in messageView(message)}
                            Color.clear.frame(height:1).id("discussion-bottom")
                        }.padding(18)
                    }.onChange(of:thread.messages.count){_,_ in proxy.scrollTo("discussion-bottom",anchor:.bottom)}
                    .onChange(of:active){_,_ in proxy.scrollTo("discussion-bottom",anchor:.bottom)}
                    .onChange(of:thread.id){_,_ in proxy.scrollTo("discussion-bottom",anchor:.bottom)}
                }
                if let error=discussion.error {
                    VStack(alignment:.leading,spacing:8){Text(error).font(.caption).foregroundStyle(.orange);HStack{Button("AI settings"){store.settingsOpen=true};Button("Retry saving"){if discussion.flush(){discussion.error=nil}};Button("Dismiss"){discussion.error=nil}}.font(.caption).buttonStyle(.plain)}.padding(12)
                }
                Divider()
                VStack(alignment:.leading,spacing:10) {
                    TextField("Ask a question…",text:Binding(get:{discussion.current?.draft ?? ""},set:{discussion.setDraft($0)}),axis:.vertical).lineLimit(2...6).textFieldStyle(.plain).onSubmit{discussion.send(store:store)}.help("Return to send. Option–Return inserts a new line.").accessibilityIdentifier("discussion.composer")
                    HStack {
                        Text("↵ Send · ⌥↵ New line").help("Conversations are saved on this Mac.").font(.system(size:10)).foregroundStyle(Palette.secondary)
                        Spacer()
                        if active {Button("Stop"){discussion.stop(thread.id)}.accessibilityIdentifier("discussion.stop")}
                        else {Button("Send"){discussion.send(store:store)}.disabled(thread.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).keyboardShortcut(.return,modifiers:.command).accessibilityIdentifier("discussion.send")}
                    }.buttonStyle(.borderedProminent)
                }.padding(16)
            }
        }.background(Palette.background)
        .sheet(isPresented:$modelOpen){if let t=thread{DiscussionModelSheet(discussion:discussion,connection:store.preferences.ai,thread:t)}}
        .sheet(isPresented:$contextOpen){if let t=thread{DiscussionContextSheet(store:store,discussion:discussion,thread:t)}}
        .sheet(isPresented:$historyOpen){DiscussionHistory(store:store,discussion:discussion)}
        .sheet(item:$source){DiscussionSourceSheet(store:store,source:$0)}
        .sheet(item:$saving){if let t=thread{DiscussionSaveSheet(store:store,discussion:discussion,threadID:t.id,message:$0)}}
    }
    @ViewBuilder private func messageView(_ m:DiscussionMessage)->some View {
        VStack(alignment:.leading,spacing:9){
            Text(m.role=="user" ? "You":m.selection).font(.system(size:11,weight:.medium)).foregroundStyle(Palette.secondary)
            if !m.text.isEmpty {
                DiscussionAnswer(message:m){selected in openSource(selected)}

            }
            if m.state=="pending" {HStack{ProgressView().controlSize(.small);Text("Thinking…").font(.caption).foregroundStyle(Palette.secondary)}}
            if let error=m.error {Text(error).font(.caption).foregroundStyle(Palette.secondary);if !active,m.id==thread?.messages.last?.id{Button("Retry answer"){discussion.send(store:store,retry:true)}.font(.caption)}}
            if m.state=="complete",m.role=="assistant" {
                if m.unknownReferences{Text("Some references could not be verified. Treat those claims as unverified.").font(.caption).foregroundStyle(.orange)}
                if !m.citedSources.isEmpty {DisclosureGroup("\(m.citedSources.count) source\(m.citedSources.count==1 ? "":"s")"){ForEach(Array(m.citedSources.enumerated()),id:\.element.id){index,s in Button{openSource(s)}label:{Text("[\(index+1)] "+s.title+" · "+s.kind).font(.caption).multilineTextAlignment(.leading)}.buttonStyle(.plain).padding(.vertical,3)}}.font(.caption)}
                HStack{Button(m.savedToNotes ? "Saved to My notes":"Save to My notes…"){saving=m}.disabled(m.savedToNotes);Spacer();Button{NSPasteboard.general.clearContents();NSPasteboard.general.setString(m.text,forType:.string)}label:{Image(systemName:"doc.on.doc")}.help("Copy answer").accessibilityLabel("Copy answer")}.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.accent)
                DisclosureGroup("Context used"){Text(m.coverage).font(.caption).foregroundStyle(Palette.secondary)}.font(.caption).foregroundStyle(Palette.secondary)
            }
        }.padding(m.role=="user" ? 12:0).frame(maxWidth:.infinity,alignment:.leading).background(m.role=="user" ? Palette.panel:Color.clear).clipShape(RoundedRectangle(cornerRadius:8))
    }
    private func openSource(_ selected:DiscussionSource) {
        if !discussion.openSource(selected,store:store){source=selected}
    }

}
struct DiscussionHistory:View {
    @ObservedObject var store:MeetingStore
    @ObservedObject var discussion:DiscussionStore
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:16){HStack{Text("Discussion history").font(.title2);Spacer();Button("Done"){dismiss()}}
            ScrollView{LazyVStack(alignment:.leading,spacing:12){ForEach(discussion.threads.filter{$0.meetingID==discussion.current?.meetingID}.sorted{$0.updated>$1.updated}){t in
                Button{discussion.select(t.id);dismiss()}label:{VStack(alignment:.leading,spacing:5){Text(t.title).foregroundStyle(Palette.ink);Text(t.scope.title+" · "+t.updated.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(Palette.secondary)}}.buttonStyle(.plain).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:7))
            }}}
        }.padding(24).frame(width:440,height:420).background(Palette.background).foregroundStyle(Palette.ink)
    }
}
struct DiscussionContextSheet:View {
    @ObservedObject var store:MeetingStore
    @ObservedObject var discussion:DiscussionStore
    let thread:DiscussionThread
    @Environment(\.dismiss) private var dismiss
    @State private var scope=DiscussionScope.meeting
    var body:some View {
        VStack(alignment:.leading,spacing:18){Text("Choose context").font(.title2)
            Picker("Context",selection:$scope){Text("This meeting").tag(DiscussionScope.meeting);Text("Whole project").tag(DiscussionScope.project).disabled(meeting?.projectID==nil)}.pickerStyle(.radioGroup)
            Text(scope == .meeting ? "This meeting's transcript, notes, summary and tasks.":"Project notes, meetings and tasks. Relevant passages are selected for each question; attachments are not read.").foregroundStyle(Palette.secondary)
            if meeting?.projectID==nil{Text("Assign this meeting to a project on the meeting page to enable project context.").font(.caption)}
            if scope != thread.scope{Text("This starts a new discussion. Your current conversation and unsent draft stay in history.").font(.caption).foregroundStyle(Palette.secondary)}
            HStack{Button("Cancel"){dismiss()};Spacer();Button(scope==thread.scope ? "Done":"Start new discussion"){if scope != thread.scope,let m=meeting{discussion.new(meeting:m,settings:thread.settings(store.preferences.ai),scope:scope);if let id=discussion.selectedID{discussion.change(id){$0.effort=thread.effort}}};dismiss()}.buttonStyle(.borderedProminent).disabled(scope == .project && meeting?.projectID==nil)}
        }.padding(24).frame(width:430).background(Palette.background).onAppear{scope=thread.scope}
    }
    private var meeting:Meeting?{store.meetings.first{$0.id==thread.meetingID && $0.deletedAt==nil}}
}
struct DiscussionSourceSheet:View {
    @ObservedObject var store:MeetingStore
    let source:DiscussionSource
    @Environment(\.dismiss) private var dismiss
    private var meeting:Meeting?{store.meetings.first{$0.id==source.meetingID && $0.deletedAt==nil}}
    private var project:MeetingProject?{store.projects.first{$0.id==source.projectID}}
    var body:some View {
        VStack(alignment:.leading,spacing:16){HStack{Text("Source passage").font(.title2);Spacer();Button("Close"){dismiss()}}
            Text(source.title).font(.headline);Text(source.kind).font(.caption).foregroundStyle(Palette.secondary)
            ScrollView{Text(source.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:340)
            Text("Saved with this answer. The original may have been edited since.").font(.caption).foregroundStyle(Palette.secondary)
            if let meeting {
                Button(source.segmentID==nil ? "Open meeting":"Open transcript at passage"){
                    store.select(meeting.id)
                    if let segment=source.segmentID {
                        if meeting.transcript.contains(where:{$0.id==segment && $0.text==source.text}){store.sourceSegment=segment;store.transcriptUsesCurrentVersion=true;store.transcriptOpen=true}
                        else{store.status="The transcript has changed. The cited passage is preserved in the discussion."}
                    }
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }else if let project{Button("Open project"){store.select("project:"+project.id);dismiss()}}
            else{Text("The original is unavailable or in Recently deleted. This saved passage is still readable.").font(.caption)}
        }.padding(24).frame(width:500).background(Palette.background).foregroundStyle(Palette.ink)
    }
}
struct DiscussionSaveSheet:View {
    @ObservedObject var store:MeetingStore
    @ObservedObject var discussion:DiscussionStore
    let threadID:String
    let message:DiscussionMessage
    @Environment(\.dismiss) private var dismiss
    @State private var text=""
    var body:some View {
        VStack(alignment:.leading,spacing:16){Text("Add to My notes").font(.title2);Text("Edit this excerpt before appending it. Your existing notes stay intact.").font(.caption).foregroundStyle(Palette.secondary)
            ScrollView{FormattedNotes(text:$text)}.frame(height:260)
            if let error=discussion.error{Text(error).font(.caption).foregroundStyle(.orange)}
            HStack{Button("Cancel"){dismiss()};Spacer();Button("Save to My notes"){if discussion.appendToNotes(store:store,threadID:threadID,messageID:message.id,text:text){dismiss()}}.buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
        }.padding(24).frame(width:510).background(Palette.background).onAppear{
            text=message.text
            let result=NSMutableString(string:message.text)
            for (range,ids) in DiscussionMessage.referenceGroups(message.text).reversed(){
                let descriptions=ids.map{id in message.sources.first{$0.id==id}.map{$0.title+", "+$0.kind} ?? "source unavailable"}
                result.replaceCharacters(in:range,with:"(Source: "+descriptions.joined(separator:"; ")+")")
            }
            text=result as String
        }
    }
}
struct DiscussionModelSheet:View {
    @ObservedObject var discussion:DiscussionStore
    let connection:AISettings
    let thread:DiscussionThread
    @Environment(\.dismiss) private var dismiss
    @State private var provider=AIProvider.claude
    @State private var model=""
    @State private var effort=""
    @State private var error:String?
    init(discussion:DiscussionStore,connection:AISettings,thread:DiscussionThread){
        self.discussion=discussion;self.connection=connection;self.thread=thread
        _provider=State(initialValue:thread.provider);_model=State(initialValue:thread.model);_effort=State(initialValue:thread.effort)
    }
    private var modelSettings:AISettings{var value=connection;value.provider=provider;return value}
    private var efforts:[String]{DiscussionModelCatalog.efforts(provider:provider,model:model)}
    var body:some View {
        VStack(alignment:.leading,spacing:18){Text("Model & reasoning effort").font(.title2)
            Picker("Provider",selection:$provider){ForEach(AIProvider.allCases){Text($0.title).tag($0)}}
            AIModelPicker(settings:modelSettings,model:$model)
            Picker("Reasoning effort",selection:$effort){ForEach(efforts,id:\.self){Text($0.isEmpty ? "Provider default":$0.capitalized).tag($0)}}
            Text(provider == .server ? "Uses the endpoint and key from AI settings. Custom server effort is left to the server.":"Applies to the next reply in this conversation. Available models depend on your account; CLI default does not identify an exact model. Effort support also depends on the model.").font(.caption).foregroundStyle(Palette.secondary)
            if let error{Text(error).font(.caption).foregroundStyle(.orange)}
            HStack{Button("Cancel"){dismiss()};Spacer();Button("Done"){
                let candidate=DiscussionThread(meetingID:thread.meetingID,provider:provider,model:model.trimmingCharacters(in:.whitespacesAndNewlines),effort:effort)
                do{_ = try candidate.settings(connection).validated();if discussion.change(thread.id,{$0.provider=provider;$0.model=candidate.model;$0.effort=effort}){dismiss()}}catch{self.error=error.localizedDescription}
            }.buttonStyle(.borderedProminent)}
        }.padding(24).frame(width:470).background(Palette.background)
        .onChange(of:provider){old,new in if old != new{model="";effort="";error=nil}}
        .onChange(of:model){_,_ in if !efforts.contains(effort){effort=""}}
    }
}

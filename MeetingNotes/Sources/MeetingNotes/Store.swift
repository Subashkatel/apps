import SwiftUI
import AVFoundation
import AppKit
import LocalSupport

@MainActor final class RecordingMeter: ObservableObject {
    @Published var mouth: CGFloat = 0
}

@MainActor final class MeetingStore: ObservableObject {
    let database: Database
    @Published var meetings: [Meeting]
    @Published var projects: [MeetingProject]
    @Published var tasks: [WorkTask]
    @Published var preferences: Preferences
    @Published var selection: String?
    @Published var settingsOpen = false
    @Published var pendingDeleteMeeting: String?
    @Published var error: String?
    @Published var status = ""
    @Published var starting = false
    @Published var activeID: String?
    @Published var drafting = Set<String>()
    @Published var transcriptionProgress: [String:String] = [:]
    @Published var sidebar = true
    @Published var sourceSegment: String?
    @Published var transcriptOpen = false
    @Published var playingID: String?
    let meter = RecordingMeter()
    var showWindow: (() -> Void)?
    private var capture: CaptureSession?
    private var meterTimer: Timer?
    private var queueBusy = false
    private var unsaved = Set<String>()
    let playback = MeetingPlayback()
    private var tick = 0
    init(root: URL = Preferences.root, recover: Bool = true) throws {
        database = try Database(root:root)
        meetings = try database.list(Meeting.self,kind:"meeting").sorted{$0.created>$1.created}
        projects = try database.list(MeetingProject.self,kind:"project").sorted{$0.name<$1.name}
        tasks = try database.list(WorkTask.self,kind:"task")
        preferences = try database.list(Preferences.self,kind:"preferences").first ?? Preferences()
        selection = meetings.first(where:{$0.deletedAt == nil})?.id
        if recover && !meetings.isEmpty { try database.backup() }
        if recover {
            for var m in meetings where m.phase == .recording {
                m.phase = .interrupted; m.ended = Date(); m.error = "Recording was interrupted. The audio on disk is retained; transcribe it or listen before continuing."
                m.captureIssue = m.error
                try database.put(m,kind:"meeting",id:m.id)
                if let i = meetings.firstIndex(where:{$0.id==m.id}) { meetings[i] = m }
            }
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval:0.05,repeats:true) { [weak self] _ in Task { @MainActor in self?.tickCapture() } }
        if recover { Task { await processQueue() } }
    }
    var current: Meeting? { meetings.first{$0.id == selection && $0.deletedAt==nil} }
    var currentProject: MeetingProject? { projects.first{"project:"+$0.id == selection} }
    var isRecording: Bool { activeID != nil }
    var busy: Bool { queueBusy || !drafting.isEmpty || starting }
    var unsavedCount: Int { unsaved.count }
    func report(_ error: Error) { self.error = error.localizedDescription }
    func select(_ id: String?) {
        if meetings.contains(where:{$0.id==id && $0.deletedAt != nil}){status="This meeting is in Recently deleted. Restore it to open it.";return}
        selection=id; transcriptOpen=false; sourceSegment=nil; stopPlayback() }
    func update(_ id: String, _ transform: (inout Meeting)->Void) {
        guard let i=meetings.firstIndex(where:{$0.id==id}) else{return}
        var m=meetings[i];transform(&m);meetings[i]=m
        do { try database.put(m,kind:"meeting",id:id);unsaved.remove(id) }
        catch {unsaved.insert(id);self.error="Your edits are still open but could not be saved. Free disk space, then choose Retry saving. " + error.localizedDescription}
    }
    @discardableResult func flush() -> Bool {
        for id in unsaved { if let m=meetings.first(where:{$0.id==id}) { do{try database.put(m,kind:"meeting",id:id);unsaved.remove(id)}catch{report(error);return false} } }
        return true
    }
    func savePreferences(_ value: Preferences, validateAI: Bool = false) {
        do { if validateAI {_ = try value.ai.validated()}; try database.put(value,kind:"preferences",id:"settings");preferences=value;settingsOpen=false }
        catch { report(error) }
    }
    func toggleMode() {
        var p=preferences;p.mode = p.mode == .microphone ? .call : .microphone
        do {try database.put(p,kind:"preferences",id:"settings");preferences=p;status=(isRecording ? "Next recording: " : "Recording mode: ")+p.mode.title} catch {report(error)}
    }
    func addProject(_ name: String) {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !name.isEmpty else{return}
        guard !projects.contains(where:{$0.name.caseInsensitiveCompare(name) == .orderedSame}) else { error="A project with that name already exists.";return }
        let p=MeetingProject(name:name)
        do{try database.put(p,kind:"project",id:p.id);projects.append(p);selection="project:"+p.id}catch{report(error)}
    }
    func addTask(_ title:String,project:String) {
        _ = saveTask(WorkTask(projectID:project,title:title,owner:"Me"))
    }
    @discardableResult func saveTask(_ input:WorkTask)->Bool {
        var task=input;task.title=task.title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !task.title.isEmpty else{error="Give the task a title.";return false}
        guard task.projectID == nil || projects.contains(where:{$0.id==task.projectID}) else{error="Choose an existing project.";return false}
        guard task.due == nil || Summarizer.validDate(task.due!) else{error="Choose a valid due date.";return false}
        guard task.dueTime == nil || (task.due != nil && Summarizer.validTime(task.dueTime!)) else{error="A due time needs a date and a valid HH:mm time.";return false}
        if let old=tasks.first(where:{$0.id==task.id}) {
            guard old.deletedAt==nil,old.revision==task.revision else{error="This task changed while you were editing it. Open it again to keep the latest changes.";return false}
            task.revision+=1;task.createdAt=old.createdAt
        } else {task.createdAt=Date()}
        task.updatedAt=Date();task.history.append(Date().formatted(date:.abbreviated,time:.shortened)+": Edited by you — "+task.title)
        do{try database.put(task,kind:"task",id:task.id);if let i=tasks.firstIndex(where:{$0.id==task.id}){tasks[i]=task}else{tasks.append(task)};return true}catch{report(error);return false}
    }
    func assignProject(_ id:String,project:String?) {
        guard !drafting.contains(id),let i=meetings.firstIndex(where:{$0.id==id}) else{return}
        guard project == nil || projects.contains(where:{$0.id==project}) else{return}
        var m=meetings[i];guard m.projectID != project else{return}
        // Saved tasks retain their independent project. Only unfiled tasks from
        // this meeting are filed automatically; existing project work is never moved.
        var changed=tasks.filter{$0.deletedAt==nil && $0.meetingID==id && $0.projectID==nil && project != nil}
        for n in changed.indices{changed[n].projectID=project;changed[n].revision+=1;changed[n].updatedAt=Date();changed[n].history.append("Filed with meeting in project")}
        m.projectID=project
        if m.draft?.applied == false {
            for n in m.draft!.changes.indices where m.draft!.changes[n].existingID != nil {
                let task=tasks.first{$0.id==m.draft!.changes[n].existingID}
                if task?.projectID != project {m.draft!.changes[n].accepted=false}
            }
        }
        do{try database.transaction{try database.put(m,kind:"meeting",id:id);for task in changed{try database.put(task,kind:"task",id:task.id)}};meetings[i]=m;for task in changed{if let n=tasks.firstIndex(where:{$0.id==task.id}){tasks[n]=task}};try database.archive(m)}catch{report(error)}
    }
    func toggleTask(_ id: String) {
        guard let i=tasks.firstIndex(where:{$0.id==id && $0.deletedAt==nil}) else{return};var t=tasks[i];t.done.toggle();t.revision+=1;t.updatedAt=Date();t.history.append(Date().formatted(date:.abbreviated,time:.omitted)+": "+(t.done ? "Completed" : "Reopened"))
        do{try database.put(t,kind:"task",id:id);tasks[i]=t}catch{report(error)}
    }
    func beginRecording() async {
        guard !starting,!isRecording,flush() else{return};starting=true;defer{starting=false}
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for:.audio) {
        case .authorized: granted=true
        case .notDetermined: granted=await AVCaptureDevice.requestAccess(for:.audio)
        default: granted=false
        }
        guard granted else { error="Enable Meeting Notes in System Settings → Privacy & Security → Microphone, then try again.";showWindow?();return }
        var m=Meeting(title:"Meeting · "+Date().formatted(date:.abbreviated,time:.shortened),projectID:preferences.preferredProject,mode:preferences.mode)
        if !projects.contains(where:{$0.id==m.projectID}) {m.projectID=nil}
        do {
            try database.archive(m);try database.put(m,kind:"meeting",id:m.id);meetings.insert(m,at:0);select(m.id)
            let session=CaptureSession(id:m.id,mode:m.mode)
            capture=session
            do { try session.start(folder:database.folder(m.id),echoCancellation:preferences.echoCancellation) }
            catch { _=session.stop();capture=nil;update(m.id){$0.phase = .failed;$0.ended=Date();$0.error=String(describing:error);$0.captureIssue=$0.error};throw error }
            activeID=m.id;status="Recording";stopPlayback()
        }catch{report(error);showWindow?()}
    }
    func stopRecording(reason: String? = nil) {
        guard let session=capture else{return}
        let offsets=session.stop();capture=nil;activeID=nil;meter.mouth=0
        update(session.id){m in m.ended=Date();m.offsets=offsets;m.error=reason;m.captureIssue=reason;m.phase = reason != nil ? .interrupted : preferences.autoTranscribe ? .transcribing : .recorded}
        if let m=meetings.first(where:{$0.id==session.id}) {do{try database.archive(m)}catch{report(error)}}
        status = reason ?? "Recording saved"
        if let reason { error=reason;showWindow?() }
        if reason == nil && flush() {Task{await processQueue()}}
    }
    private func tickCapture() {
        let mouth = meter.mouth
        let target = preferences.animateBear && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? capture?.mouthLevel ?? 0 : 0
        let value=mouth+(target-mouth)*(target>mouth ? 0.55:0.3)
        let next=value<0.015 ? 0 : value
        if abs(next-mouth)>0.02 || (next==0 && mouth != 0) {meter.mouth=next}
        tick+=1
        if tick%20==0,let problem=capture?.error {stopRecording(reason:problem)}
    }
    func transcribe(_ id: String) {
        guard id != activeID,!drafting.contains(id),transcriptionProgress[id]==nil,flush() else{return}
        update(id){$0.phase = .transcribing;$0.error=nil}
        Task{await processQueue()}
    }
    func processQueue() async {
        guard !queueBusy,unsaved.isEmpty else{return};queueBusy=true;defer{queueBusy=false}
        while let m=meetings.first(where:{$0.phase == .transcribing && $0.deletedAt == nil}) {
            let config=preferences,folder=database.folder(m.id)
            transcriptionProgress[m.id]="Preparing audio…"
            do {
                let segments=try await Task.detached(priority:.utility) {
                    try Transcription.run(meeting:m,folder:folder,preferences:config){progress in Task{@MainActor [weak self] in self?.transcriptionProgress[m.id]=progress}}
                }.value
                if segments.isEmpty && !m.transcript.isEmpty {throw MeetingError("The new attempt detected no speech. Your previous transcript has been kept.")}
                var archived = meetings.first(where:{$0.id==m.id}) ?? m;archived.transcript=segments;archived.phase = .ready;try database.archive(archived)
                update(m.id){$0.transcript=segments;$0.phase = .ready;$0.error=segments.isEmpty ? "No speech was detected. You can listen to the original audio or retry with another model." : nil}
            }catch{update(m.id){$0.phase = .failed;$0.error=error.localizedDescription}}
            transcriptionProgress[m.id]=nil
            if !unsaved.isEmpty {break}
        }
    }
    func summarize(_ id: String) async {
        guard !drafting.contains(id),id != activeID,let m=meetings.first(where:{$0.id==id}),flush() else{return}
        let prefs=preferences,taskSnapshot=tasks,prior=meetings.filter{$0.id != id && $0.deletedAt == nil}.sorted{$0.created>$1.created}
        drafting.insert(id);defer{drafting.remove(id)}
        do {
            _=try prefs.ai.validated()
            let draft=try await Task.detached {try Summarizer.make(meeting:m,tasks:taskSnapshot,related:prior,preferences:prefs)}.value
            // Keep text typed while the request was running. The draft stores its original snapshot.
            update(id){$0.receiveDraft(draft,requestedTitle:m.title)}
        }catch{update(id){$0.error=error.localizedDescription};report(error)}
    }
    func findTasks(_ id:String) async {
        guard !drafting.contains(id),id != activeID,let m=meetings.first(where:{$0.id==id}),
              let old=m.draft,old.changes.isEmpty,old.appliedTaskIDs.isEmpty,flush() else{return}
        let prefs=preferences,existing=tasks
        drafting.insert(id);defer{drafting.remove(id)}
        do {
            try database.backup(force:true)
            var source=m;source.transcript=old.sourceTranscript ?? m.transcript
            let result=try await Task.detached{try Summarizer.make(meeting:source,tasks:existing,related:[],preferences:prefs)}.value
            update(id){meeting in
                // Preserve the edited summary, notes, decisions and original AI attribution.
                meeting.draft?.changes=result.changes
                meeting.draft?.sourceTranscript=source.transcript
                if !result.changes.isEmpty{meeting.draft?.applied=false}
                meeting.error=nil
            }
            if let updated=meetings.first(where:{$0.id==id}){try database.archive(updated)}
            status=result.changes.isEmpty ? "No supported tasks found in the transcript." : "Task suggestions recovered. Review them before saving."
        }catch{report(error)}
    }
    func saveDraft(_ id: String) {
        guard flush(),let m=meetings.first(where:{$0.id==id}) else{return}
        do {
            let (meeting,updatedTasks)=try Reconcile.apply(meeting:m,tasks:tasks)
            var project=projects.first{$0.id==m.projectID}
            if m.draft?.applied != true,let question=meeting.draft?.question,!question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {project?.question=question}
            try database.transaction {
                try database.put(meeting,kind:"meeting",id:id)
                for t in updatedTasks where tasks.first(where:{$0.id==t.id}) != t {try database.put(t,kind:"task",id:t.id)}
                if let project{try database.put(project,kind:"project",id:project.id)}
            }
            if let i=meetings.firstIndex(where:{$0.id==id}){meetings[i]=meeting}
            tasks=updatedTasks
            if let project,let i=projects.firstIndex(where:{$0.id==project.id}){projects[i]=project}
            try database.archive(meeting)
            try Self.markdown(meeting).write(to:database.folder(id).appendingPathComponent("meeting-note.md"),atomically:true,encoding:.utf8)
            try database.backup()
            status="Meeting note saved"
        }catch{report(error)}
    }
    func meetingTasks(_ id:String)->[WorkTask]{tasks.filter{$0.meetingID==id && $0.deletedAt==nil}}
    @discardableResult func deleteTask(_ id:String)->Bool {
        guard let i=tasks.firstIndex(where:{$0.id==id && $0.deletedAt==nil}) else{return false}
        var task=tasks[i];task.deletedAt=Date();task.deletedWithMeetingID=nil;task.revision+=1;task.updatedAt=Date();task.history.append("Moved to Trash")
        do{try database.put(task,kind:"task",id:id);tasks[i]=task;status="Task moved to Recently deleted";return true}catch{report(error);return false}
    }
    func restoreTask(_ id:String) {
        guard let i=tasks.firstIndex(where:{$0.id==id && $0.deletedAt != nil}) else{return}
        var task=tasks[i];task.deletedAt=nil;task.deletedWithMeetingID=nil;task.revision+=1;task.updatedAt=Date();task.history.append("Restored from Trash")
        do{try database.put(task,kind:"task",id:id);tasks[i]=task;status="Task restored"}catch{report(error)}
    }
    func delete(_ id:String,includingTasks:Bool=false) {
        guard id != activeID,transcriptionProgress[id]==nil,!drafting.contains(id),flush() else{error="Stop recording or wait for processing before moving this meeting to Trash.";return}
        guard let i=meetings.firstIndex(where:{$0.id==id && $0.deletedAt==nil}) else{return}
        var meeting=meetings[i];meeting.deletedAt=Date()
        var changed=includingTasks ? meetingTasks(id):[]
        for n in changed.indices{changed[n].deletedAt=meeting.deletedAt;changed[n].deletedWithMeetingID=id;changed[n].revision+=1;changed[n].updatedAt=Date();changed[n].history.append("Moved to Trash with source meeting")}
        do{
            try database.transaction{try database.put(meeting,kind:"meeting",id:id);for t in changed{try database.put(t,kind:"task",id:t.id)}}
            meetings[i]=meeting;for t in changed{if let n=tasks.firstIndex(where:{$0.id==t.id}){tasks[n]=t}}
            if selection==id{select(meetings.first(where:{$0.deletedAt==nil})?.id)}
            status=includingTasks ? "Meeting and \(changed.count) tasks moved to Recently deleted":"Meeting moved to Recently deleted; its tasks were kept"
            try database.archive(meeting)
        }catch{report(error)}
    }
    func restore(_ id:String) {
        guard let i=meetings.firstIndex(where:{$0.id==id && $0.deletedAt != nil}) else{return}
        var meeting=meetings[i];meeting.deletedAt=nil
        var changed=tasks.filter{$0.deletedAt != nil && $0.deletedWithMeetingID==id}
        for n in changed.indices{changed[n].deletedAt=nil;changed[n].deletedWithMeetingID=nil;changed[n].revision+=1;changed[n].updatedAt=Date();changed[n].history.append("Restored with source meeting")}
        do{
            try database.transaction{try database.put(meeting,kind:"meeting",id:id);for t in changed{try database.put(t,kind:"task",id:t.id)}}
            meetings[i]=meeting;for t in changed{if let n=tasks.firstIndex(where:{$0.id==t.id}){tasks[n]=t}}
            select(id);try database.archive(meeting)
        }catch{report(error)}
    }
    func reveal(_ id: String){NSWorkspace.shared.activateFileViewerSelecting([database.folder(id)])}
    func play(_ meeting: Meeting, segment: Segment? = nil, track: String = "mic") {
        do {
            stopPlayback();let chosen=segment?.track ?? track
            try playback.open(database.folder(meeting.id).appendingPathComponent(chosen+".caf"),meetingID:meeting.id,track:chosen,at:max(0,(segment?.start ?? 0)-(meeting.offsets[chosen] ?? 0)))
            playingID=meeting.id
        }catch{report(error)}
    }
    func stopPlayback(){playback.stop();playingID=nil}
    func export(_ meeting: Meeting) {
        let panel=NSSavePanel();panel.allowedContentTypes=[.plainText];panel.nameFieldStringValue=LocalFiles.safeName(meeting.title)+".md"
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do{try Self.markdown(meeting).write(to:url,atomically:true,encoding:.utf8)}catch{report(error)}
    }
    static func markdown(_ m: Meeting)->String {
        var text="# \(m.title)\n\n\(m.created.formatted(date:.long,time:.shortened))\n"
        if let d=m.draft {
            text+="\n\(d.summary)\n"
            if !d.decision.isEmpty{text+="\n## Decided\n\(d.decision)\n"}
            if !d.question.isEmpty{text+="\n## Still open\n\(d.question)\n"}
            text+="\nDrafted with \(d.provider) · \(d.model)\n"
        }
        text+="\n## My notes\n\(m.notes)\n\n## Transcript\n"
        for s in m.transcript{text+="\n[\(s.time)] \(s.speaker): \(s.text)\n"}
        return text
    }
}

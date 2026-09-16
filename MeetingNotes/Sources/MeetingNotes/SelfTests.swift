import Foundation
import AVFoundation
import LocalSupport

@MainActor enum SelfTests {
    static func require(_ condition:@autoclosure()->Bool,_ message:String)throws{if !condition(){throw MeetingError(message)}}
    static func run() throws {
        try require(!AppLaunchMode.isPreview(bundleID:"local.meetingnotes",arguments:[]),"Installed app incorrectly treated as a preview")
        try require(AppLaunchMode.isPreview(bundleID:"local.meetingnotes.filtersqa",arguments:[]),"Reopening a test bundle could access real data")
        try require(AppLaunchMode.isPreview(bundleID:"local.meetingnotes",arguments:["--ui-inspect"]),"Explicit UI test mode lost isolation")
        try CalendarTests.run()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("meetingnotes-check-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let db=try Database(root:root)
        let project=MeetingProject(name:"Test project")
        var m=Meeting(title:"Synthetic meeting",projectID:project.id,mode:.microphone)
        m.phase = .ready;m.ended=Date();m.notes="Keep uncertainty."
        m.transcript=[Segment(id:"seg1",track:"mic",start:1,end:4,text:"I will compare the slow cases tomorrow."),Segment(id:"seg2",track:"system",start:5,end:8,text:"Morgan will check the assumptions.")]
        let t=WorkTask(projectID:project.id,title:"Compare timings",owner:"Me",history:["Created"])
        let unrelated=WorkTask(projectID:project.id,title:"Other work",owner:"")
        m.draft=MeetingDraft(summary:"We discussed slow cases.",decision:"Compare two datasets.",question:"Are bursts important?",changes:[TaskChange(existingID:t.id,expectedRevision:0,title:"Compare slow cases",owner:"Me",evidence:["seg1"]),TaskChange(title:"Check assumptions",owner:"Morgan",evidence:["seg2"])],evidence:["seg1"],provider:"Test",model:"fixture",originalNotes:m.notes)
        try db.transaction{try db.put(project,kind:"project",id:project.id);try db.put(m,kind:"meeting",id:m.id);try db.put(t,kind:"task",id:t.id)}
        do{try db.transaction{try db.put(unrelated,kind:"task",id:unrelated.id);throw MeetingError("rollback")}}catch{}
        try require(tryCount(db)==1,"Transaction rollback failed")
        let (saved,tasks)=try Reconcile.apply(meeting:m,tasks:[t,unrelated])
        try require(tasks.count==3 && tasks[0].title=="Compare slow cases" && tasks[1]==unrelated,"Task reconciliation failed")
        let (_,again)=try Reconcile.apply(meeting:saved,tasks:tasks)
        try require(again==tasks,"Repeated save duplicated changes")
        var stale=t;stale.revision=1
        do{_=try Reconcile.apply(meeting:m,tasks:[stale]);throw MeetingError("Accepted stale task") }catch let e as MeetingError{try require(e.message != "Accepted stale task","Stale revision not rejected")}
        var unfiled=m;unfiled.projectID=nil
        unfiled.draft?.changes=[TaskChange(title:"Check assumptions",owner:"Morgan",evidence:["seg2"])]
        let (unfiledSaved,unfiledTasks)=try Reconcile.apply(meeting:unfiled,tasks:[t])
        try require(unfiledTasks.count==2 && unfiledTasks[0]==t && unfiledTasks[1].projectID==nil && unfiledTasks[1].meetingID==m.id,"Unfiled task was lost or changed another project")
        let (_,unfiledAgain)=try Reconcile.apply(meeting:unfiledSaved,tasks:unfiledTasks)
        try require(unfiledAgain==unfiledTasks,"Unfiled task duplicated on repeat save")
        try db.put(unfiledTasks[1],kind:"task",id:unfiledTasks[1].id)
        let reopenedTasks=try db.list(WorkTask.self,kind:"task")
        try require(reopenedTasks.contains(unfiledTasks[1]) && reopenedTasks.contains(t),"Optional project migration lost existing or unfiled tasks")
        var selective=m;selective.draft?.changes[1].accepted=false
        let (_,one)=try Reconcile.apply(meeting:selective,tasks:[t]);try require(one.count==1,"Unchecked task applied")
        try db.archive(m);try db.backup()
        try require(FileManager.default.fileExists(atPath:db.folder(m.id).appendingPathComponent("transcript.json").path),"Transcript not independently retained")
        var revised=m;revised.transcript[0].text="Corrected transcription."
        try db.archive(revised)
        let versions=try FileManager.default.contentsOfDirectory(at:db.folder(m.id).appendingPathComponent("Transcript versions"),includingPropertiesForKeys:nil)
        try require(versions.count==1,"Retry discarded the previous transcript")
        let loaded=try Database(root:root).list(Meeting.self,kind:"meeting");try require(loaded.first==m,"Database reload differs")
        try require(Summarizer.validDate("2026-09-18") && !Summarizer.validDate("2026-02-30"),"Date validation failed")
        let json="""
        {"summary":"We discussed timing.","decision":"Compare two datasets.","question":"Do bursts matter?","evidence":["seg1"],"changes":[{"existingID":null,"title":"Check assumptions","owner":"Morgan","due":null,"evidence":["seg2"]}],"relatedMeetingID":null,"relatedReason":null}
        """
        let legacyDraft=try Summarizer.decode(json,meeting:m,tasks:[t],related:[],config:AISettings())
        try require(legacyDraft.topics == nil && legacyDraft.summary == "We discussed timing.","Legacy summary was changed when no topics were supplied")
        let legacyData=try JSONEncoder().encode(legacyDraft)
        let legacyReload=try JSONDecoder().decode(MeetingDraft.self,from:legacyData)
        try require(legacyReload == legacyDraft,"An older draft without topics no longer loads")
        var topicResponse=try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [String:Any]
        let topicText="- Timing assumptions\n- Bursty arrivals"
        topicResponse["topics"]=topicText
        let topicDraft=try Summarizer.decode(String(decoding:try JSONSerialization.data(withJSONObject:topicResponse),as:UTF8.self),meeting:m,tasks:[t],related:[],config:AISettings())
        var topicMeeting=m;topicMeeting.draft=topicDraft
        let topicDB=try Database(root:root.appendingPathComponent("topic-check"))
        try topicDB.put(topicMeeting,kind:"meeting",id:topicMeeting.id)
        let topicReload=try topicDB.list(Meeting.self,kind:"meeting")[0]
        try require(topicReload.draft?.topics == topicText && topicReload.draft?.summary == legacyDraft.summary,"Topics and detailed summary did not persist independently")
        let exported=MeetingStore.markdown(topicReload)
        try require(exported.contains("## What we talked about\n"+topicText) && exported.contains("## Detailed summary\n"+legacyDraft.summary),"Export dropped the topics or detailed summary")
        print("PASS older summaries preserved and separate topics/detail survive persistence and export")
        let unfiledDraft=try Summarizer.decode(json,meeting:unfiled,tasks:[],related:[],config:AISettings())
        try require(unfiledDraft.changes.count==1,"Unfiled task suggestions were discarded")
        let titledJSON=json.replacingOccurrences(of:"\"summary\":",with:"\"title\":\"Research timing\",\"summary\":").replacingOccurrences(of:"\"due\":null",with:"\"due\":\"2026-09-20\",\"dueTime\":\"16:30\"")
        let titled=try Summarizer.decode(titledJSON,meeting:unfiled,tasks:[],related:[],config:AISettings())
        try require(titled.suggestedTitle=="Research timing" && titled.changes[0].dueTime=="16:30","AI title or due time lost in decode")
        var forSave=unfiled;forSave.draft=titled
        let (_,dated)=try Reconcile.apply(meeting:forSave,tasks:[])
        try require(dated[0].dueTime=="16:30","Saving an AI task dropped its due time")
        var automatic=Meeting(title:"Meeting · today",mode:.microphone)
        var named=unfiledDraft;named.suggestedTitle="Decoder experiment planning"
        automatic.receiveDraft(named,requestedTitle:automatic.title)
        try require(automatic.title=="Decoder experiment planning","Automatic title was not applied")
        automatic.title="My own title";automatic.titleEdited=true
        automatic.receiveDraft(named,requestedTitle:automatic.title)
        try require(automatic.title=="My own title","Manual title was overwritten")
        let managementRoot=root.appendingPathComponent("management")
        let management=try MeetingStore(root:managementRoot,recover:false)
        try require(!management.isMonitoringCapture,"Idle app is running the recording animation timer")
        management.addProject("Research")
        let projectID=management.projects[0].id
        var personal=WorkTask(title:"Write comparison",owner:"Me",due:"2026-09-20",dueTime:"16:30",meetingID:unfiledSaved.id)
        try require(management.saveTask(personal),"Manual unfiled task creation failed")
        personal=management.tasks[0];personal.title="Write full comparison"
        try require(management.saveTask(personal),"Task edit failed")
        try require(!management.saveTask(personal),"Stale manual edit was accepted")
        management.error=nil
        var invalid=personal;invalid.id="invalid";invalid.dueTime="25:99"
        try require(!management.saveTask(invalid),"Invalid due time accepted")
        management.error=nil
        try management.database.put(unfiledSaved,kind:"meeting",id:unfiledSaved.id)
        management.meetings=[unfiledSaved]
        management.assignProject(unfiledSaved.id,project:projectID)
        try require(management.meetings[0].draft==unfiledSaved.draft && management.meetings[0].notes==unfiledSaved.notes,"Filing replaced a summary or notes")
        try require(management.tasks[0].projectID==projectID,"Unfiled meeting task was not filed")
        management.update(unfiledSaved.id){$0.notes="## My understanding\n**Evidence** and *uncertainty*\n- Follow up"}
        let reload=try MeetingStore(root:managementRoot,recover:false)
        try require(reload.tasks[0].dueTime=="16:30" && reload.tasks[0].title=="Write full comparison" && reload.tasks[0].createdAt != nil,"Task details did not survive reload")
        try require(reload.meetings[0].notes.contains("**Evidence**"),"Formatted personal notes did not survive reload")
        print("PASS manual tasks, stale edits, due date/time, project filing, title preservation and formatted note persistence")
        var overdue=WorkTask(id:"overdue",projectID:projectID,title:"Past task",owner:"Me",due:"2026-09-13",meetingID:unfiledSaved.id)
        var later=WorkTask(id:"later",title:"Later task",owner:"Other",due:"2026-09-20")
        var query=TaskQuery()
        try require(query.results([later,overdue],today:"2026-09-14").first?.id=="overdue","Due date sorting failed")
        query.project=projectID;query.meeting=unfiledSaved.id;query.deadline="overdue"
        try require(query.results([later,overdue],today:"2026-09-14").map(\.id)==["overdue"],"Combined task filters failed")
        overdue.done=true;query=TaskQuery();query.status="done"
        try require(query.results([later,overdue]).count==1,"Completed task filter failed")
        later.due=nil;query=TaskQuery();query.deadline="none";query.search="Other"
        try require(query.results([later,overdue]).map(\.id)==["later"],"Undated/owner search failed")
        var history:[Meeting]=[]
        for index in 0..<6 {var entry=unfiledSaved;entry.id="prior-\(index)";entry.projectID=projectID;entry.created=Date(timeIntervalSince1970:Double(index));entry.notes="Personal context \(index)";history.append(entry)}
        var current=unfiledSaved;current.projectID=projectID
        var foreign=current;foreign.id="foreign";foreign.projectID="elsewhere";history.append(foreign)
        let allContext=ProjectContext.make(for:current,from:history)
        try require(allContext.entries.count==6 && allContext.entries.first?.id=="prior-5" && !allContext.json.contains("foreign"),"Project context missed meetings or leaked another project")
        let bounded=ProjectContext.make(for:current,from:history,limit:600)
        try require(bounded.omitted>0 && bounded.json.utf8.count<=600,"Context omissions or bounds are incorrect")
        let original=root.appendingPathComponent("Reference notes.txt")
        try "Attachment evidence".write(to:original,atomically:true,encoding:.utf8)
        let attached=try db.importAttachment(original,meetingID:m.id)
        try FileManager.default.removeItem(at:original)
        let attachmentCopy=try String(contentsOf:db.attachmentURL(attached,meetingID:m.id)!,encoding:.utf8)
        try require(attachmentCopy=="Attachment evidence","Moving original broke attachment")
        var traversal=attached;traversal.storedName="../outside"
        try require(db.attachmentURL(traversal,meetingID:m.id)==nil,"Unsafe stored attachment path accepted")
        var attachmentMeeting=m;attachmentMeeting.attachments=[attached]
        try db.put(attachmentMeeting,kind:"meeting",id:m.id)
        let attachmentReload=try db.list(Meeting.self,kind:"meeting").first{$0.id==m.id}
        try require(attachmentReload?.attachments==[attached],"Attachment metadata lost on reopen")
        print("PASS central task filtering/sorting, complete bounded project context, independent attachment copies and metadata reload")
        let trashStore=try MeetingStore(root:root.appendingPathComponent("trash-check"),recover:false)
        var trashMeeting=unfiledSaved;trashMeeting.id="trash-meeting"
        try trashStore.database.put(trashMeeting,kind:"meeting",id:trashMeeting.id);trashStore.meetings=[trashMeeting]
        let sourceTask=WorkTask(id:"source-task",title:"Source work",owner:"Me",meetingID:trashMeeting.id)
        let independent=WorkTask(id:"independent",title:"Other work",owner:"Me")
        try require(trashStore.saveTask(sourceTask) && trashStore.saveTask(independent),"Trash fixture setup failed")
        let staleSource=trashStore.tasks.first{$0.id==sourceTask.id}!
        trashStore.deleteTask(sourceTask.id)
        try require(!TaskQuery().results(trashStore.tasks).contains{$0.id==sourceTask.id},"Deleted task stayed in active list")
        try require(!trashStore.saveTask(staleSource),"An open editor resurrected a deleted task")
        trashStore.error=nil;trashStore.restoreTask(sourceTask.id)
        trashStore.delete(trashMeeting.id)
        try require(trashStore.tasks.first{$0.id==sourceTask.id}?.deletedAt==nil,"Keep-tasks deletion removed task")
        trashStore.select("tasks");trashStore.select(trashMeeting.id)
        try require(trashStore.selection=="tasks" && trashStore.current==nil,"Task navigation reopened a deleted meeting")
        trashStore.restore(trashMeeting.id)
        let previouslyDeleted=WorkTask(id:"already-deleted",title:"Old work",owner:"Me",meetingID:trashMeeting.id)
        try require(trashStore.saveTask(previouslyDeleted),"Independent trash fixture failed")
        trashStore.deleteTask(previouslyDeleted.id)
        trashStore.delete(trashMeeting.id,includingTasks:true)
        try require(trashStore.tasks.first{$0.id==sourceTask.id}?.deletedAt != nil && trashStore.tasks.first{$0.id==independent.id}?.deletedAt==nil,"Meeting/task deletion affected unrelated work")
        let trashReload=try MeetingStore(root:trashStore.database.root,recover:false)
        try require(trashReload.tasks.first{$0.id==sourceTask.id}?.deletedAt != nil,"Task trash was lost on reopen")
        trashStore.restore(trashMeeting.id)
        try require(trashStore.tasks.first{$0.id==sourceTask.id}?.deletedAt==nil && trashStore.tasks.first{$0.id==previouslyDeleted.id}?.deletedAt != nil,"Meeting restore resurrected independently deleted task")
        var removedTask=t;removedTask.deletedAt=Date()
        do{_=try Reconcile.apply(meeting:m,tasks:[removedTask]);throw MeetingError("Updated deleted task")}catch let e as MeetingError{try require(e.message != "Updated deleted task","Deleted task accepted AI update")}
        print("PASS task Trash/reload/restore, deleted source navigation, keep-vs-delete meeting tasks, unrelated task preservation and stale editor protection")
        let longTranscript=(0..<1000).map{Segment(id:"long-\($0)",track:"mic",start:Double($0)*7.2,end:Double($0+1)*7.2,text:String(repeating:"A technical discussion. ",count:30))}
        let batches=try Summarizer.partitions(longTranscript)
        try require(batches.count>1 && batches.flatMap{$0}==longTranscript,"Long summary partitioning dropped or reordered passages")
        for batch in batches{let data=try JSONEncoder().encode(batch);try require(data.count<=100_002,"Summary section exceeded bounded size")}
        var longMeeting=unfiled;longMeeting.transcript=longTranscript
        var calls=0
        let merged=try Summarizer.make(meeting:longMeeting,tasks:[],related:[],preferences:Preferences(),request:{prompt in
            let refs=calls<batches.count ? [batches[calls][0].id] : batches.map{$0[0].id}
            calls+=1
            let response:[String:Any] = ["summary":"Combined discussion with supporting reasoning.","topics":"- Main discussion topic","decision":"","question":"","evidence":refs,"changes":refs.map{["title":"Action from "+$0,"owner":"Me","evidence":[$0]] as [String:Any]}]
            return String(decoding:try JSONSerialization.data(withJSONObject:response),as:UTF8.self)
        })
        try require(calls==batches.count+1 && merged.changes.count==batches.count,"Long summary merge lost section tasks")
        try require(merged.topics == "- Main discussion topic" && merged.summary == "Combined discussion with supporting reasoning.","Long meeting merge replaced detail with topics")
        print("PASS long transcript batching and multi-section task merge with local mock responses")
        let cache=root.appendingPathComponent("summary-resume")
        func mockSection(_ prompt:String)throws->String {
            let response:[String:Any] = ["summary":"Detailed discussion preserved.","topics":"- Timing","decision":"","question":"","evidence":[],"changes":[]]
            return String(decoding:try JSONSerialization.data(withJSONObject:response),as:UTF8.self)
        }
        var interruptedCalls=0
        do {
            _=try Summarizer.make(meeting:longMeeting,tasks:[],related:[],preferences:Preferences(),request:{prompt in
                interruptedCalls+=1
                if interruptedCalls==2{throw MeetingError("Synthetic temporary failure")}
                return try mockSection(prompt)
            },cacheRoot:cache)
            throw MeetingError("Expected a simulated failure")
        }catch let error as MeetingError{try require(error.message=="Synthetic temporary failure","Unexpected checkpoint failure")}
        var resumedCalls=0
        let resumed=try Summarizer.make(meeting:longMeeting,tasks:[],related:[],preferences:Preferences(),request:{prompt in resumedCalls+=1;return try mockSection(prompt)},cacheRoot:cache)
        try require(resumedCalls==batches.count && resumed.summary=="Detailed discussion preserved.","Retry did not reuse completed sections or lost detail")
        var freshCalls=0
        _=try Summarizer.make(meeting:longMeeting,tasks:[],related:[],preferences:Preferences(),request:{prompt in freshCalls+=1;return try mockSection(prompt)},cacheRoot:cache)
        try require(freshCalls==batches.count+1,"A deliberate new draft incorrectly reused completed generation")
        let parsedModels=AvailableAIModel.parse("Fetching available models…\nexample-model\tExample model\nexample-model\tDuplicate\ninvalid model\tInvalid\n")
        try require(parsedModels==[AvailableAIModel(id:"example-model",title:"Example model")],"Model picker accepted malformed entries or duplicates")
        print("PASS failed long summaries resume saved sections, new drafts start fresh, and model catalog parsing")
        let badEvidence=try Summarizer.decode(json.replacingOccurrences(of:"seg2",with:"invented"),meeting:m,tasks:[t],related:[],config:AISettings())
        try require(badEvidence.changes.isEmpty && badEvidence.deferredTasks?.count==1 && badEvidence.summary==legacyDraft.summary,"Invalid task evidence lost the summary or became an accepted task")
        var mixed=try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [String:Any]
        let valid:[String:Any] = ["existingID":t.id,"title":"Updated comparison","evidence":["seg1"]]
        mixed["changes"]=[valid,valid,["existingID":"missing-task","title":"Unmatched action","evidence":["seg2"]],["title":"New action","evidence":["seg2"]]]
        let mixedJSON=String(decoding:try JSONSerialization.data(withJSONObject:mixed),as:UTF8.self)
        let resilient=try Summarizer.decode(mixedJSON,meeting:m,tasks:[t],related:[],config:AISettings())
        try require(resilient.summary==legacyDraft.summary && resilient.changes.count==2 && resilient.deferredTasks?.count==2,"Repeated or unknown task IDs rejected the whole summary")
        var recovered=m;recovered.draft=resilient
        let (_,safeTasks)=try Reconcile.apply(meeting:recovered,tasks:[t])
        try require(safeTasks.count==2 && safeTasks.first{$0.id==t.id}?.revision==1,"Deferred tasks were applied or duplicate updates escaped validation")
        let standalone=try Summarizer.decode(mixedJSON,meeting:unfiled,tasks:[t],related:[],config:AISettings())
        try require(standalone.changes.count==1 && standalone.changes[0].existingID==nil && standalone.deferredTasks?.count==3,"Standalone meeting accessed another project's tasks")
        let reviewReload=try JSONDecoder().decode(MeetingDraft.self,from:JSONEncoder().encode(resilient))
        try require(reviewReload.deferredTasks==resilient.deferredTasks,"Deferred suggestions lost on reload")
        try require(management.needsProjectChoice(unfiled),"New standalone meeting skipped project choice")
        var confirmed=unfiled;confirmed.projectChoiceConfirmed=true
        try require(!management.needsProjectChoice(confirmed),"Standalone choice was not remembered")
        confirmed.projectID="missing"
        try require(management.needsProjectChoice(confirmed),"Missing project passed preflight")
        try require(management.saveProjectNotes(projectID,notes:"Compare tail latency; preserve assumptions."),"Project notes failed to save")
        let notesReload=try Database(root:management.database.root).list(MeetingProject.self,kind:"project")
        try require(notesReload.first{$0.id==projectID}?.notes=="Compare tail latency; preserve assumptions.","Project notes did not persist")
        let legacyProject=try JSONDecoder().decode(MeetingProject.self,from:Data("{\"id\":\"old\",\"name\":\"Existing\",\"question\":\"\"}".utf8))
        try require(legacyProject.notes==nil,"Older projects failed migration")
        let responseRoot=root.appendingPathComponent("retained-response")
        _=try Summarizer.make(meeting:unfiled,tasks:[],related:[],preferences:Preferences(),projectNotes:"Purpose fixture",request:{prompt in
            try require(prompt.contains("Purpose fixture") && prompt.contains("ALL existingID values must be null"),"Project context or task identity rules omitted from prompt")
            return mixedJSON
        },cacheRoot:responseRoot)
        let responseFiles=try FileManager.default.contentsOfDirectory(atPath:responseRoot.appendingPathComponent("Responses").path)
        try require(responseFiles.count==1,"Original AI response was not retained")
        print("PASS repeated/missing task recovery, standalone isolation, safe apply, project preflight/notes migration, and retained responses")
        let raw=Data("{\"transcription\":[{\"offsets\":{\"from\":1000,\"to\":2500},\"text\":\" A phrase.\"}]}".utf8)
        let segments=try Transcription.parse(raw,track:"system",offset:3,prefix:"test")
        try require(segments.first?.start==4 && segments.first?.end==5.5,"Track offset alignment failed")
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let audioURL=root.appendingPathComponent("audio.caf")
        let sink=try AudioSink(url:audioURL,format:format)
        for chunk in 0..<30 {
            let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:2048)!;buffer.frameLength=2048
            for n in 0..<2048{buffer.floatChannelData![0][n]=Float(sin(Double(n+chunk*2048)*2*Double.pi*440/48000)*0.1)}
            sink.append(buffer)
        }
        sink.close();try require(sink.snapshot.error==nil && sink.snapshot.frames==61440,"Audio writer dropped frames")
        let audio=try AVAudioFile(forReading:audioURL);try require(audio.length==61440,"Audio file length incorrect")
        let converted=root.appendingPathComponent("converted");try FileManager.default.createDirectory(at:converted,withIntermediateDirectories:true)
        let chunks=try Transcription.chunks(source:audioURL,directory:converted)
        let wav=try AVAudioFile(forReading:chunks[0].url)
        try require(abs(Double(wav.length)/16000-1.28)<0.01,"Streaming resample duration incorrect")
        try require(chunks[0].peak>0.05,"Audio conversion lost signal")
        let interruptedAudio=root.appendingPathComponent("interrupted.caf")
        let child=Process();child.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);child.arguments=["--crash-audio-check",interruptedAudio.path]
        try child.run();child.waitUntilExit()
        try require(child.terminationStatus==0,"Interrupted writer fixture failed")
        let recoveredAudio=try AVAudioFile(forReading:interruptedAudio)
        try require(recoveredAudio.length==61440,"Abrupt exit lost written PCM audio")
        var interrupted=Meeting(title:"Interrupted fixture",mode:.call)
        try db.put(interrupted,kind:"meeting",id:interrupted.id)
        let recoveredStore=try MeetingStore(root:root)
        interrupted=recoveredStore.meetings.first{$0.id==interrupted.id}!
        try require(interrupted.phase == .interrupted && interrupted.captureIssue != nil,"Interrupted recording was not recovered")
        print("PASS abrupt process exit preserves PCM frames; startup marks interrupted recordings recoverable")
        let worker=TranscriptionProcess(),job=DispatchGroup()
        DispatchQueue.global().async(group:job){try? worker.run(URL(fileURLWithPath:"/bin/sleep"),arguments:["10"],directory:root,timeout:20)}
        Thread.sleep(forTimeInterval:0.15);worker.cancelAll()
        try require(job.wait(timeout:.now()+3) == .success,"Whisper child cancellation did not finish")
        print("PASS transcript version retention and owned transcription child cancellation")
        print("PASS database reload/rollback/backup, source archives, reconciliation/idempotence/stale revisions/selective/unfiled, source validation, track timing, PCM capture and streaming resample")
    }
    private static func tryCount(_ db:Database)->Int{(try? db.list(WorkTask.self,kind:"task").count) ?? -1}
    static func writeUnclosedAudio(_ url:URL)throws {
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let sink=try AudioSink(url:url,format:format)
        for _ in 0..<30 {
            let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:2048)!;buffer.frameLength=2048
            for n in 0..<2048{buffer.floatChannelData![0][n]=0.1}
            sink.append(buffer)
        }
        sink.flushWrites()
        guard sink.snapshot.error==nil else{throw MeetingError("Fixture write failed")}
        // Intentionally bypass AVAudioFile deinitialization/finalization.
        withExtendedLifetime(sink){_exit(0)}
    }
    static func transcribeFile(_ source:URL)throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("meetingnotes-speech-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.copyItem(at:source,to:root.appendingPathComponent("mic.caf"))
        var m=Meeting(title:"Synthetic speech test",mode:.microphone);m.phase = .recorded
        let result=try Transcription.run(meeting:m,folder:root,preferences:Preferences()){print($0)}
        try require(!result.isEmpty,"No speech transcribed")
        print(result.map{"[\($0.time)] \($0.text)"}.joined(separator:"\n"))
    }
    static func longAudio(_ source:URL)throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("long-audio-check-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let chunks=try Transcription.chunks(source:source,directory:folder)
        var seconds:Double=0
        for chunk in chunks {
            let file=try AVAudioFile(forReading:chunk.url)
            try require(abs(chunk.offset-seconds)<0.01,"Long recording has a gap or overlap")
            let duration=Double(file.length)/file.fileFormat.sampleRate
            try require(duration<=600.3,"Unbounded transcription chunk")
            seconds+=duration
        }
        try require(abs(seconds-7200)<0.1,"Two-hour recording duration changed")
        try require(chunks.count==12,"Unexpected two-hour chunk count")
        print("PASS two-hour audio conversion: 12 bounded chunks, 7200 seconds, no gaps or overlaps")
        let playback=MeetingPlayback();try playback.open(source,meetingID:"long-test",track:"mic")
        playback.toggle();playback.seek(3600)
        try require(abs(playback.duration-7200)<0.1 && abs(playback.position-3600)<0.01,"Playback could not seek halfway through two-hour audio")
        playback.seek(-50);try require(playback.position==0,"Negative seek not clamped")
        playback.seek(8000);try require(playback.position==7200,"Seek exceeded recording duration")
        playback.stop()
        print("PASS two-hour playback load, pause, midpoint seeking and seek bounds")
    }
}

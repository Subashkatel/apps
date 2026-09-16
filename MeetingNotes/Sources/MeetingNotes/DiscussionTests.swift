import Foundation
import LocalSupport

@MainActor enum DiscussionTests {
    static func run()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("discussion-tests-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=try MeetingStore(root:root,recover:false),d=store.discussion
        let project=MeetingProject(name:"Synthetic project",notes:"We study latency.")
        var meeting=Meeting(title:"First review",projectID:project.id,mode:.microphone,phase:.ready,notes:"My existing note.")
        meeting.transcript=[Segment(id:"s1",track:"mic",start:12,end:16,text:"Morgan will compare the two datasets on Friday.")]
        var other=Meeting(title:"Second review",projectID:project.id,mode:.microphone,phase:.ready)
        other.transcript=[Segment(id:"s2",track:"mic",start:20,end:24,text:"The project target is fifteen milliseconds.")]
        var excluded=Meeting(title:"Private other project",mode:.microphone,phase:.ready,notes:"SECRET OUTSIDE CONTEXT")
        excluded.transcript=[Segment(id:"s3",track:"mic",start:0,end:1,text:"Do not include.")]
        store.meetings=[meeting,other,excluded];store.projects=[project];store.selection=meeting.id
        try store.database.put(meeting,kind:"meeting",id:meeting.id)
        var config=AISettings();config.executablePath="/usr/bin/true"
        store.preferences.ai=config
        d.open(meeting:meeting,settings:config)
        let first=d.current!.id
        d.setDraft("What did Morgan agree to do?");d.close();d.open(meeting:meeting,settings:config)
        try SelfTests.require(d.current?.draft=="What did Morgan agree to do?","Close/reopen lost draft")
        let reloaded=try DiscussionStore(database:store.database)
        try SelfTests.require(reloaded.threads.first?.draft==d.current?.draft,"Draft not durable")
        let local=try DiscussionContext.build(thread:d.current!,meeting:meeting,meetings:store.meetings,projects:store.projects,tasks:[],question:"Morgan")
        try SelfTests.require(!local.sources.contains{$0.text.contains("fifteen") || $0.text.contains("SECRET")},"Meeting context included another meeting")
        let cite=local.sources.first{$0.segmentID=="s1"}!.id
        d.responder={prompt,settings,effort,token in
            guard prompt.contains("Morgan"),!prompt.contains("SECRET OUTSIDE CONTEXT"),effort=="low" else{throw MeetingError("Request settings/context mismatch")}
            try token.check();return "Morgan agreed to compare two datasets [\(cite)]."
        }
        d.change(first){$0.model="sonnet";$0.effort="low"}
        d.send(store:store);try await idle(d)
        try SelfTests.require(d.current?.messages.count==2 && d.current?.messages.last?.state=="complete","Send failed")
        let response=d.current!.messages.last!
        try SelfTests.require(response.citedSources.count==1 && !response.unknownReferences,"Citation resolution failed")
        try SelfTests.require(response.selection.contains("sonnet") && response.selection.contains("Low"),"Reply model/effort provenance lost")
        try SelfTests.require(d.appendToNotes(store:store,threadID:first,messageID:response.id,text:"My edited takeaway."),"Save note failed")
        try SelfTests.require(store.current?.notes=="My existing note.\n\nMy edited takeaway.","Append overwrote notes")
        try SelfTests.require(!d.appendToNotes(store:store,threadID:first,messageID:response.id,text:"Duplicate"),"Duplicate excerpt saved")
        d.error=nil
        d.responder={prompt,_,_,_ in
            guard prompt.contains("Morgan agreed to compare two datasets"),prompt.contains("Why does that matter?") else{throw MeetingError("Follow-up lost history")}
            return "It makes the comparison testable."
        }
        d.setDraft("Why does that matter?");d.send(store:store);d.setDraft("Unsent next question");try await idle(d)
        try SelfTests.require(d.current?.messages.last?.state=="complete" && d.current?.draft=="Unsent next question","Follow-up/draft preservation failed")
        d.new(meeting:meeting,settings:config,scope:.project)
        let wide=try DiscussionContext.build(thread:d.current!,meeting:meeting,meetings:store.meetings,projects:store.projects,tasks:[],question:"target")
        try SelfTests.require(wide.sources.contains{$0.text.contains("fifteen")} && !wide.sources.contains{$0.text.contains("SECRET")},"Project isolation failed")
        let bounded=try DiscussionContext.build(thread:d.current!,meeting:meeting,meetings:store.meetings,projects:store.projects,tasks:[],question:"target",limit:150)
        try SelfTests.require(bounded.coverage.contains("not the full archive"),"Truncation was hidden")
        d.new(meeting:meeting,settings:config,scope:.meeting)
        try SelfTests.require(d.current!.messages.isEmpty,"Context switch leaked prior messages")
        d.select(first);try SelfTests.require(d.current?.draft=="Unsent next question" && d.current?.model=="sonnet","History did not restore draft/model")
        d.responder={_,_,_,token in while !token.isCancelled{Thread.sleep(forTimeInterval:0.01)};throw CancellationError()}
        d.send(store:store);try await Task.sleep(for:.milliseconds(50));d.stop(first);try await idle(d)
        try SelfTests.require(d.current?.messages.last?.state=="stopped","Stop did not cancel request")
        let before=d.current!.messages.filter{$0.role=="user"}.count
        d.responder={_,_,_,_ in throw MeetingError("Synthetic provider failure")}
        d.send(store:store,retry:true);try await idle(d)
        try SelfTests.require(d.current?.messages.last?.state=="failed" && d.current!.messages.filter{$0.role=="user"}.count==before,"Retry duplicated question or hid failure")
        d.responder={_,_,_,_ in "Recovered answer"};d.send(store:store,retry:true);try await idle(d)
        try SelfTests.require(d.current?.messages.last?.text=="Recovered answer","Retry failed to recover")
        d.change(first){$0.messages.append(DiscussionMessage(role:"assistant",text:"",state:"pending"))}
        let restart=try DiscussionStore(database:store.database)
        try SelfTests.require(restart.threads.first{$0.id==first}?.messages.last?.state=="stopped","Interrupted request stuck after restart")
        var invalid=DiscussionMessage(role:"assistant",text:"Claim [Sunknown]",sources:local.sources)
        try SelfTests.require(invalid.unknownReferences && invalid.citedSources.isEmpty,"Invented reference accepted")
        invalid.text="Valid [\(cite)]";try SelfTests.require(invalid.citedSources.count==1,"Valid reference rejected")
        var removed=meeting;removed.deletedAt=Date()
        do{_ = try DiscussionContext.build(thread:d.current!,meeting:removed,meetings:[removed],projects:[],tasks:[],question:"test");throw MeetingError("Deleted meeting sent")}
        catch let e as MeetingError{try SelfTests.require(e.message != "Deleted meeting sent","Deleted context not blocked")}
        let transcriptSource=local.sources.first{$0.segmentID=="s1"}!
        let secondSource=local.sources.first{$0.kind=="My notes"}!
        let grouped=DiscussionMessage(role:"assistant",text:"Together [\(transcriptSource.id), \(secondSource.id)]. Again [\(secondSource.id); Sunknown].",sources:local.sources)
        try SelfTests.require(grouped.citedSources.count==2 && grouped.unknownReferences,"Grouped citations not parsed")
        try SelfTests.require(!grouped.linkedText.contains("["+transcriptSource.id) && grouped.linkedText.contains("meeting-source://") && grouped.linkedText.contains("source unavailable"),"Citation display leaked internal IDs")
        try SelfTests.require(d.openSource(transcriptSource,store:store),"Live source did not navigate directly")
        try SelfTests.require(store.transcriptOpen && store.transcriptUsesCurrentVersion && store.sourceSegment=="s1","Citation did not select the current transcript passage")
        var changed=transcriptSource;changed.text="Old text no longer in transcript"
        try SelfTests.require(!d.openSource(changed,store:store),"Changed source incorrectly navigated as current")
        for provider in [AIProvider.claude,.codex,.gemini] {
            var s=config;s.provider=provider
            let args=s.arguments(effort:"high")
            try SelfTests.require(provider == .codex ? args.contains("model_reasoning_effort=\"high\"") : args.contains("--effort"),"Effort argument missing")
        }
        // Exercise the real subprocess stop path, not just the injected responder.
        let token=AICancellation()
        let job=Task.detached{Result{try LocalProcess.run(URL(fileURLWithPath:"/bin/sleep"),arguments:["30"],timeout:40,cancellation:token)}}
        try await Task.sleep(for:.milliseconds(150));let start=Date();token.cancel()
        let result=await job.value
        if case .success=result{throw MeetingError("Cancelled process returned success")}
        try SelfTests.require(Date().timeIntervalSince(start)<4,"Stop did not terminate owned process promptly")
        print("PASS discussion: durable drafts/history, send/follow-up, model/effort, source validation, context isolation, notes append/idempotency, stop/retry/restart and subprocess cancellation")
    }
    static func idle(_ d:DiscussionStore)async throws {
        let deadline=Date().addingTimeInterval(8)
        while !d.running.isEmpty && Date()<deadline{try await Task.sleep(for:.milliseconds(20))}
        try SelfTests.require(d.running.isEmpty,"Discussion did not finish")
    }
    static func live(provider:AIProvider)throws {
        var settings=AISettings();settings.provider=provider
        switch provider{case .claude:settings.claudeModel="sonnet";case .codex:settings.codexModel=DiscussionModelCatalog.codex().first{$0.slug.contains("sol")}?.slug ?? "";case .gemini:settings.geminiModel=try AvailableAIModel.load(settings).first{$0.id.contains("flash") && $0.id.contains("low")}?.id;case .server:throw MeetingError("Live server check requires configured endpoint")}
        var meeting=Meeting(title:"Synthetic provider check",mode:.microphone,phase:.ready)
        meeting.transcript=[Segment(id:"check-1",track:"mic",start:10,end:12,text:"Morgan will compare two datasets on Friday. The agreed target is fifteen milliseconds.")]
        var thread=DiscussionThread(meetingID:meeting.id,provider:provider,model:settings.model,effort:"low")
        let context=try DiscussionContext.build(thread:thread,meeting:meeting,meetings:[meeting],projects:[],tasks:[],question:"What did Morgan agree to do?")
        let question="What did Morgan agree to do? Answer in one sentence and cite the transcript."
        let answer=try AIClient.ask(context.prompt(thread:thread,question:question),settings:settings,timeout:120,effort:"low")
        let reply=DiscussionMessage(role:"assistant",text:answer,sources:context.sources)
        try SelfTests.require(!reply.citedSources.isEmpty && !reply.unknownReferences,"Live citation missing or invented: "+provider.title)
        thread.messages=[DiscussionMessage(role:"user",text:question),reply]
        let follow=try AIClient.ask(context.prompt(thread:thread,question:"What target did we agree on? Answer briefly with a source."),settings:settings,timeout:120,effort:"low")
        let next=DiscussionMessage(role:"assistant",text:follow,sources:context.sources)
        try SelfTests.require(!next.citedSources.isEmpty && !next.unknownReferences && (follow.contains("15") || follow.lowercased().contains("fifteen")),"Live follow-up lost context")
        print("PASS live discussion: \(settings.selectionLabel), low effort, two turns, valid source references")
    }
}

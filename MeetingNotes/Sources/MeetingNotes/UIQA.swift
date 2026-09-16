import AppKit
import SwiftUI
import Carbon.HIToolbox
import LocalSupport

@MainActor enum UIQA {
    static func fixture(root:URL)throws {
        let db=try Database(root:root)
        let p=MeetingProject(id:"qa-project",name:"Decoder research",notes:"Understand tail latency and compare the assumptions behind two decoder experiments.")
        let m=meeting()
        var prefs=Preferences();prefs.globalShortcuts=false
        try db.transaction{try db.put(p,kind:"project",id:p.id);try db.put(m,kind:"meeting",id:m.id);try db.put(prefs,kind:"preferences",id:"settings")}
    }
    static func meeting()->Meeting {
        var m=Meeting(id:"qa-meeting",title:"Research catch-up",projectID:"qa-project",mode:.microphone)
        m.phase = .ready;m.ended=Date();m.notes="Look at the slow cases, not just averages.\nKeep the comparison small for now."
        m.transcript=[Segment(id:"qa-1",track:"mic",start:6,end:11,text:"We should compare two data sets before changing the experiment. The dashboard can wait."),Segment(id:"qa-2",track:"system",start:14,end:19,text:"Morgan here. I will write down the assumptions behind the comparison."),Segment(id:"qa-3",track:"mic",start:21,end:28,text:"Would bursty arrivals change the result? We haven't decided how to test that yet.")]
        return m
    }
    static func run(store:MeetingStore,window:NSWindow,output:URL) async throws {
        let discussionPreference=UserDefaults.standard.object(forKey:"meetingDiscussionExpanded")
        defer{if let discussionPreference{UserDefaults.standard.set(discussionPreference,forKey:"meetingDiscussionExpanded")}else{UserDefaults.standard.removeObject(forKey:"meetingDiscussionExpanded")}}
        UserDefaults.standard.set(true,forKey:"meetingDiscussionExpanded")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func snapshot(_ name:String) throws {
            guard let view=(window.sheets.first ?? window).contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{throw MeetingError("Could not render native UI")}
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        }
        try SelfTests.require(NSApp.activationPolicy() == .regular,"Open notebook is missing its Dock presence")
        window.performClose(nil)
        try SelfTests.require(NSApp.activationPolicy() == .accessory,"Closing notebook should leave a menu-bar app")
        (NSApp.delegate as? MeetingAppDelegate)?.openWindow()
        try SelfTests.require(NSApp.activationPolicy() == .regular,"Reopening did not restore Dock presence")
        print("PASS Dock presence with window open and background menu-bar mode after close")
        try await Task.sleep(for:.milliseconds(450));try snapshot("ready")
        store.update("qa-meeting"){$0.draft=MeetingDraft(summary:"We need to look at the slow cases, not just the average. I want the comparison to show when a decoder falls behind and what assumptions we are making. Bursty arrivals may change the outcome, so an average alone could hide the behavior that matters.",decision:"We'll compare two datasets before changing the experiment. The dashboard can wait.",question:"Would bursty arrivals change the result? We haven't decided how to test that yet.",changes:[TaskChange(title:"Write down the assumptions behind the comparison",owner:"Morgan",evidence:["qa-2"])],evidence:["qa-1","qa-3"],provider:"Claude",model:"CLI default · exact model not reported",originalNotes:$0.notes,topics:"- Decoder latency beyond averages\n- Comparison assumptions and bursty arrivals")}
        store.update("qa-meeting"){$0.draft?.deferredTasks=[DeferredTask(title:"Compare the latency measurements",reason:"The task it proposes updating is not available in this meeting or project.",response:"{\"title\":\"Compare the latency measurements\",\"owner\":\"Morgan\",\"evidence\":[\"qa-1\"]}")]}
        try await Task.sleep(for:.milliseconds(350));try snapshot("draft")
        UserDefaults.standard.set(false,forKey:"meetingDiscussionExpanded")
        try await Task.sleep(for:.milliseconds(250));try snapshot("discussion-collapsed")
        UserDefaults.standard.set(true,forKey:"meetingDiscussionExpanded")
        store.transcriptOpen=true;store.sourceSegment="qa-2"
        try await Task.sleep(for:.milliseconds(250));try snapshot("transcript")
        store.transcriptOpen=false;store.saveDraft("qa-meeting")
        try SelfTests.require(store.tasks.count==1,"UI store did not save task")
        store.select("project:qa-project")
        try await Task.sleep(for:.milliseconds(250));try snapshot("project")
        store.toggleTask(store.tasks[0].id);store.saveDraft("qa-meeting")
        try SelfTests.require(store.tasks.count==1 && store.tasks[0].done,"Repeat save changed a completed task")
        store.select("qa-meeting");store.sidebar=false
        try await Task.sleep(for:.milliseconds(250));try snapshot("focused")
        store.delete("qa-meeting");try SelfTests.require(store.meetings[0].deletedAt != nil,"Trash failed")
        store.restore("qa-meeting");try SelfTests.require(store.meetings[0].deletedAt == nil,"Restore failed")
        let savedTask=store.tasks[0].id
        store.deleteTask(savedTask);store.saveDraft("qa-meeting")
        try SelfTests.require(store.tasks.first{$0.id==savedTask}?.deletedAt != nil,"Saving note resurrected deleted task")
        store.restoreTask(savedTask)
        store.delete("qa-meeting",includingTasks:true)
        try SelfTests.require(store.tasks.first{$0.id==savedTask}?.deletedAt != nil,"Meeting deletion did not trash its tasks")
        store.select("tasks");store.select("qa-meeting")
        try SelfTests.require(store.current==nil,"Deleted meeting reopened through selection")
        store.restore("qa-meeting")
        try SelfTests.require(store.tasks.first{$0.id==savedTask}?.deletedAt==nil,"Meeting restoration did not restore its tasks")
        print("PASS deleted task stays deleted after note save, meeting/task cascade and deleted-meeting navigation")
        store.update("qa-meeting"){$0.projectID=nil;$0.projectChoiceConfirmed=nil}
        let beforeChoice=store.meetings[0].draft
        await store.summarize("qa-meeting")
        try SelfTests.require(store.pendingSummaryID=="qa-meeting" && store.drafting.isEmpty && store.meetings[0].draft==beforeChoice,"Project preflight started AI or changed the existing draft")
        try await Task.sleep(for:.milliseconds(350));try snapshot("project-choice")
        store.pendingSummaryID=nil
        store.assignProject("qa-meeting",project:nil)
        try SelfTests.require(!store.needsProjectChoice(store.meetings[0]),"Standalone choice was not remembered")
        let reloadedChoice=try store.database.list(Meeting.self,kind:"meeting")[0]
        try SelfTests.require(reloadedChoice.projectChoiceConfirmed==true && reloadedChoice.projectID==nil,"Standalone choice did not persist")
        print("PASS project choice blocks AI before generation, preserves existing draft, and remembers standalone choice")
        try await Task.sleep(for:.milliseconds(200))
        store.settingsOpen=true
        try await Task.sleep(for:.milliseconds(350));try snapshot("settings")
        store.settingsOpen=false
        store.sidebar=true;store.transcriptOpen=true
        window.setContentSize(NSSize(width:780,height:650))
        try await Task.sleep(for:.milliseconds(350));try snapshot("narrow")
        var light=store.preferences;light.appearance="light";store.savePreferences(light)
        try await Task.sleep(for:.milliseconds(350));try snapshot("light")
        store.transcriptOpen=false;store.select("qa-meeting")
        var dark=store.preferences;dark.appearance="dark";store.savePreferences(dark)
        store.discussion.open(meeting:store.current!,settings:store.preferences.ai)
        let thread=store.discussion.current!
        let context=try DiscussionContext.build(thread:thread,meeting:store.current!,meetings:store.meetings,projects:store.projects,tasks:store.tasks,question:"assumptions")
        let source=context.sources.first{$0.segmentID=="qa-2"}!
        store.discussion.change(thread.id){$0.messages=[DiscussionMessage(role:"user",text:"What should I question about our comparison?"),DiscussionMessage(role:"assistant",text:"Start with the assumptions Morgan agreed to write down [\(source.id)].\n\n- Are the workloads comparable?\n- Could bursty arrivals change the result?\n\nThe meeting leaves that second question open. Try stating your hypothesis before choosing an experiment.",selection:"Claude · sonnet · Medium",sources:context.sources,coverage:context.coverage)]}
        window.setContentSize(NSSize(width:1180,height:800))
        try await Task.sleep(for:.milliseconds(350));try snapshot("discussion-wide")
        window.setContentSize(NSSize(width:780,height:650))
        try await Task.sleep(for:.milliseconds(350));try snapshot("discussion-narrow")
        store.transcriptOpen=true
        try await Task.sleep(for:.milliseconds(350));try snapshot("discussion-transcript")
        store.discussion.close()
        for chicken in [false,true]{for level:CGFloat in [0,1]{let image=BearIcon.image(level:level,active:true,chicken:chicken);if let rep=NSBitmapImageRep(data:image.tiffRepresentation!){try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(chicken ? "chicken":"bear")-\(Int(level)).png"))}}}
        let reopened=try Database(root:store.database.root).list(Meeting.self,kind:"meeting")
        try SelfTests.require(reopened.first?.draft?.applied==true,"Saved meeting lost on reopen")
        let key=try MeetingHotKey(key:kVK_F19,modifiers:controlKey|optionKey|cmdKey){}
        var duplicateRejected=false
        do{_ = try MeetingHotKey(key:kVK_F19,modifiers:controlKey|optionKey|cmdKey){}}catch{duplicateRejected=true}
        try SelfTests.require(duplicateRejected,"Duplicate hotkey registration was not rejected")
        withExtendedLifetime(key){}
        store.select("tasks");store.sidebar=true;store.transcriptOpen=false
        for width:CGFloat in [1180,780] {
            window.setContentSize(NSSize(width:width,height:740))
            try await Task.sleep(for:.milliseconds(350));try snapshot("task-filters-"+String(Int(width)))
        }
        store.select("project:qa-project")
        try await Task.sleep(for:.milliseconds(350));try snapshot("task-filters-project")
        var lightFilters=store.preferences;lightFilters.appearance="light";store.savePreferences(lightFilters)
        try await Task.sleep(for:.milliseconds(350));try snapshot("task-filters-light")
        var darkFilters=store.preferences;darkFilters.appearance="dark";store.savePreferences(darkFilters)
        for provider in [AIProvider.claude,.codex] {
            var config=store.preferences.ai;config.provider=provider
            let available=try DiscussionModelCatalog.load(config)
            let chosen=provider == .claude ? "fable":(available.first?.id ?? "")
            if provider == .claude{try SelfTests.require(available.contains{$0.id=="fable"},"Claude model selector missing Fable")}
            window.contentMinSize=NSSize(width:570,height:240)
            window.contentView=NSHostingView(rootView:VStack(alignment:.leading,spacing:18){Text(provider.title+" · Model selector").font(.title2);AIModelPicker(settings:config,model:.constant(chosen))}.padding(24).frame(width:570,height:240).background(Palette.background).foregroundStyle(Palette.ink).preferredColorScheme(.dark))
            window.setContentSize(NSSize(width:570,height:240))
            try await Task.sleep(for:.milliseconds(600));try snapshot("model-picker-"+provider.rawValue)
        }
        for scheduled in [false,true] {
            let task=WorkTask(title:"Review experiment assumptions",owner:"Me",due:scheduled ? "2026-09-18":nil)
            let draft=CalendarDraft.task(task,project:"Decoder research")
            window.contentView=NSHostingView(rootView:CalendarSheet(draft:draft,store:store).preferredColorScheme(.dark))
            window.setContentSize(NSSize(width:536,height:620))
            try await Task.sleep(for:.milliseconds(350));try snapshot(scheduled ? "calendar-dated-task":"calendar-choose-date")
        }
        print("PASS global shortcut registration and collision detection")
        print("PASS native window render, transcript selection, note/task save, repeated save, focus sidebar, trash/restore and reopen")
    }
}

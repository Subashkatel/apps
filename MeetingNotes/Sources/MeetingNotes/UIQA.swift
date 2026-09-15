import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor enum UIQA {
    static func fixture(root:URL)throws {
        let db=try Database(root:root)
        let p=MeetingProject(id:"qa-project",name:"Decoder research")
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
        store.update("qa-meeting"){$0.draft=MeetingDraft(summary:"We need to look at the slow cases, not just the average. I want the comparison to show when a decoder falls behind and what assumptions we're making.",decision:"We'll compare two datasets before changing the experiment. The dashboard can wait.",question:"Would bursty arrivals change the result? We haven't decided how to test that yet.",changes:[TaskChange(title:"Write down the assumptions behind the comparison",owner:"Morgan",evidence:["qa-2"])],evidence:["qa-1","qa-3"],provider:"Claude",model:"CLI default · exact model not reported",originalNotes:$0.notes)}
        try await Task.sleep(for:.milliseconds(350));try snapshot("draft")
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
        store.settingsOpen=true
        try await Task.sleep(for:.milliseconds(350));try snapshot("settings")
        store.settingsOpen=false
        store.sidebar=true;store.transcriptOpen=true
        window.setContentSize(NSSize(width:780,height:650))
        try await Task.sleep(for:.milliseconds(350));try snapshot("narrow")
        var light=store.preferences;light.appearance="light";store.savePreferences(light)
        try await Task.sleep(for:.milliseconds(350));try snapshot("light")
        for chicken in [false,true]{for level:CGFloat in [0,1]{let image=BearIcon.image(level:level,active:true,chicken:chicken);if let rep=NSBitmapImageRep(data:image.tiffRepresentation!){try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(chicken ? "chicken":"bear")-\(Int(level)).png"))}}}
        let reopened=try Database(root:store.database.root).list(Meeting.self,kind:"meeting")
        try SelfTests.require(reopened.first?.draft?.applied==true,"Saved meeting lost on reopen")
        let key=try MeetingHotKey(key:kVK_F19,modifiers:controlKey|optionKey|cmdKey){}
        var duplicateRejected=false
        do{_ = try MeetingHotKey(key:kVK_F19,modifiers:controlKey|optionKey|cmdKey){}}catch{duplicateRejected=true}
        try SelfTests.require(duplicateRejected,"Duplicate hotkey registration was not rejected")
        withExtendedLifetime(key){}
        print("PASS global shortcut registration and collision detection")
        print("PASS native window render, transcript selection, note/task save, repeated save, focus sidebar, trash/restore and reopen")
    }
}

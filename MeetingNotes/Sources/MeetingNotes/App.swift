import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import AVFoundation
import LocalSupport

@main @MainActor enum MeetingNotesMain {
    static func main() {
        if CommandLine.arguments.contains("--wake-check") {do{let wake=RecordingWakeLock();try wake.start();Thread.sleep(forTimeInterval:3);wake.stop();print("PASS recording idle-sleep assertion created and released");exit(0)}catch{print("FAIL: \(error)");exit(1)}}
        if let i=CommandLine.arguments.firstIndex(of:"--long-audio-check"),CommandLine.arguments.count>i+1 {do{try SelfTests.longAudio(URL(fileURLWithPath:CommandLine.arguments[i+1]));exit(0)}catch{print("FAIL: \(error)");exit(1)}}
        if CommandLine.arguments.contains("--self-test") {do{try SelfTests.run();exit(0)}catch{print("FAIL: \(error)");exit(1)}}
        if let i=CommandLine.arguments.firstIndex(of:"--crash-audio-check"),CommandLine.arguments.count>i+1 {
            do { try SelfTests.writeUnclosedAudio(URL(fileURLWithPath:CommandLine.arguments[i+1])) } catch { exit(1) }
        }
        if CommandLine.arguments.contains("--ai-check") {
            do{var prefs=Preferences();if let i=CommandLine.arguments.firstIndex(of:"--provider"),CommandLine.arguments.count>i+1{prefs.ai.provider=LocalSupport.AIProvider(rawValue:CommandLine.arguments[i+1]) ?? .claude}
                let draft=try Summarizer.make(meeting:UIQA.meeting(),tasks:[],related:[],preferences:prefs)
                print("PASS live AI structured summary: "+draft.provider+"; "+String(draft.changes.count)+" sourced tasks")
                exit(0)
            }catch{print("FAIL: \(error)");exit(1)}
        }
        if let i=CommandLine.arguments.firstIndex(of:"--transcribe-file"),CommandLine.arguments.count>i+1 {
            do{try SelfTests.transcribeFile(URL(fileURLWithPath:CommandLine.arguments[i+1]));exit(0)}catch{print("FAIL: \(error)");exit(1)}
        }
        let app=NSApplication.shared
        let delegate=MeetingAppDelegate();app.delegate=delegate;app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate){app.run()}
    }
}
@MainActor final class MeetingAppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    private var store:MeetingStore!
    private var window:NSWindow!
    private var statusItem:NSStatusItem!
    private var subscriptions=Set<AnyCancellable>()
    private var hotKeys:[MeetingHotKey]=[]
    private var shortcutSetting:Bool?
    private var lastIcon=""
    private var modePopup:NSPopover?
    func applicationDidFinishLaunching(_ notification:Notification) {
        let others=NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "local.meetingnotes").filter{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}
        if let existing=others.first{existing.activate();NSApp.terminate(nil);return}
        do{
            if CommandLine.arguments.contains("--ui-check") || CommandLine.arguments.contains("--ui-inspect") {
                let root=FileManager.default.temporaryDirectory.appendingPathComponent("meetingnotes-ui-"+UUID().uuidString)
                try UIQA.fixture(root:root);store=try MeetingStore(root:root,recover:false)
            }else{store=try MeetingStore()}
        }catch{let alert=NSAlert();alert.messageText="Meeting Notes could not open its data";alert.informativeText=error.localizedDescription+"\nThe existing files have not been replaced.";alert.addButton(withTitle:"Open data folder");alert.addButton(withTitle:"Quit");if alert.runModal() == .alertFirstButtonReturn{NSWorkspace.shared.open(Preferences.root)};NSApp.terminate(nil);return}
        if let url=Bundle.main.url(forResource:"AppIcon",withExtension:"icns"),let icon=NSImage(contentsOf:url){NSApp.applicationIconImage=icon}
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1060,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Meeting Notes";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false;window.delegate=self
        window.contentView=NSHostingView(rootView:MeetingRoot(store:store));window.center()
        store.showWindow = { [weak self] in self?.openWindow() }
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.target=self;statusItem.button?.action=#selector(statusClick);statusItem.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        buildMainMenu()
        store.objectWillChange.sink{[weak self] _ in DispatchQueue.main.async{self?.refresh()}}.store(in:&subscriptions)
        store.meter.objectWillChange.sink{[weak self] _ in DispatchQueue.main.async{self?.refreshIcon()}}.store(in:&subscriptions)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(willSleep),name:NSWorkspace.willSleepNotification,object:nil)
        refresh();openWindow()
        if let i=CommandLine.arguments.firstIndex(of:"--ui-check"),CommandLine.arguments.count>i+1 {
            let output=URL(fileURLWithPath:CommandLine.arguments[i+1])
            Task {do{try await UIQA.run(store:store,window:window,output:output);window.orderOut(nil);exit(0)}catch{print("FAIL UI: \(error)");exit(1)}}
        }
        if CommandLine.arguments.contains("--capture-check") {Task{await captureCheck()}}
        if let i=CommandLine.arguments.firstIndex(of:"--recover-tasks"),CommandLine.arguments.count>i+1 {
            let id=CommandLine.arguments[i+1];store.select(id);Task{await store.findTasks(id)}
        }
    }
    func openWindow(){guard window != nil else{return};NSApp.setActivationPolicy(.regular);window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool{openWindow();return true}
    func windowShouldClose(_ sender:NSWindow)->Bool{store.flush();sender.orderOut(nil);NSApp.setActivationPolicy(.accessory);return false}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard store != nil else{return .terminateNow}
        if store.isRecording || store.busy || store.unsavedCount>0 {
            let alert=NSAlert();alert.messageText="Quit Meeting Notes?";alert.informativeText="Recording will stop and the saved audio will be retained. Unfinished transcription resumes when you reopen the app.";alert.addButton(withTitle:"Keep running");alert.addButton(withTitle:"Stop and quit")
            guard alert.runModal() == .alertSecondButtonReturn else{return .terminateCancel}
        }
        store.stopRecording();guard store.flush() else{return .terminateCancel};TranscriptionProcess.shared.cancelAll();return .terminateNow
    }
    @objc private func willSleep(){if store.isRecording{store.stopRecording(reason:"Recording stopped because the Mac went to sleep. Audio already captured is saved.")}}
    private func refresh(){
        refreshIcon()
        guard store != nil else{return}
        window.appearance=NSAppearance(named:store.preferences.appearance == "light" ? .aqua:.darkAqua)
        let hex:UInt32=store.preferences.appearance == "light" ? 0xf7f5ed:0x22251f
        window.backgroundColor=NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)
        window.titlebarSeparatorStyle = .none
        if shortcutSetting != store.preferences.globalShortcuts {registerShortcuts()}
    }
    private func refreshIcon(){
        guard store != nil,statusItem != nil else{return}
        let active=store.isRecording
        let mode=store.meetings.first{$0.id==store.activeID}?.mode ?? store.preferences.mode
        let level=(store.meter.mouth*5).rounded()/5
        let key="\(active)-\(mode.rawValue)-\(level)"
        if key != lastIcon{statusItem.button?.image=BearIcon.image(level:level,active:active,chicken:mode == .call);lastIcon=key}
        let next=store.preferences.mode.title
        statusItem.button?.toolTip=(active ? "Recording · ":"Ready · ")+mode.title+"\nClick to \(active ? "stop":"start"). Right-click for options."+(active && mode != store.preferences.mode ? "\nNext: "+next:"")
        statusItem.button?.setAccessibilityLabel((active ? "Stop recording":"Start recording")+", "+mode.title)
    }
    private func registerShortcuts(){
        shortcutSetting=store.preferences.globalShortcuts;hotKeys=[]
        guard store.preferences.globalShortcuts else{return}
        do {
            hotKeys.append(try MeetingHotKey(key:kVK_ANSI_R,modifiers:controlKey|optionKey){[weak self] in self?.toggle()})
            // Jot already owns Control-Option-S on this Mac.
            hotKeys.append(try MeetingHotKey(key:kVK_ANSI_S,modifiers:controlKey|optionKey|cmdKey){[weak self] in self?.store.stopRecording()})
            hotKeys.append(try MeetingHotKey(key:kVK_ANSI_M,modifiers:controlKey|optionKey){[weak self] in self?.switchMode()})
        }catch{store.report(error)}
    }
    private func toggle(){guard !store.starting else{return};if store.isRecording{store.stopRecording()}else{Task{await store.beginRecording()}}}
    @objc private func statusClick(){if NSApp.currentEvent?.type == .rightMouseUp {contextMenu()}else{toggle()}}
    private func contextMenu(){
        let menu=NSMenu()
        item(menu,store.isRecording ? "Stop recording":"Start recording",#selector(toggleAction))
        item(menu,"Open meeting notes",#selector(openAction))
        menu.addItem(.separator())
        item(menu,(store.preferences.mode == .microphone ? "✓ ":"")+"Bear · In person",#selector(micMode))
        item(menu,(store.preferences.mode == .call ? "✓ ":"")+"Chicken · Online meeting",#selector(callMode))
        if store.isRecording{let label=NSMenuItem(title:"Mode changes apply to the next recording",action:nil,keyEquivalent:"");label.isEnabled=false;menu.addItem(label)}
        menu.addItem(.separator());item(menu,"Settings…",#selector(settingsAction));item(menu,"Quit Meeting Notes",#selector(quitAction))
        statusItem.menu=menu;statusItem.button?.performClick(nil);statusItem.menu=nil
    }
    private func item(_ menu:NSMenu,_ title:String,_ action:Selector,_ key:String=""){let i=NSMenuItem(title:title,action:action,keyEquivalent:key);i.target=self;menu.addItem(i)}
    @objc private func toggleAction(){toggle()}
    @objc private func startAction(){Task{await store.beginRecording()}}
    @objc private func stopAction(){store.stopRecording()}
    @objc private func openAction(){openWindow()}
    @objc private func settingsAction(){openWindow();store.settingsOpen=true}
    @objc private func quitAction(){NSApp.terminate(nil)}
    @objc private func micMode(){setMode(.microphone)}
    @objc private func callMode(){setMode(.call)}
    private func setMode(_ mode:CaptureMode){if store.preferences.mode != mode{switchMode()}}
    private func switchMode(){store.toggleMode();refresh();let popover=NSPopover();popover.behavior = .transient;popover.contentSize=NSSize(width:250,height:65);popover.contentViewController=NSHostingController(rootView:Text((store.isRecording ? "Next recording: ":"")+(store.preferences.mode == .microphone ? "Bear · In person":"Chicken · Online meeting")).font(.system(size:13,weight:.medium)).padding(16));modePopup?.close();modePopup=popover;if let button=statusItem.button{popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)};DispatchQueue.main.asyncAfter(deadline:.now()+1.5){[weak popover] in popover?.close()}}
    private func buildMainMenu(){
        let root=NSMenu(),app=NSMenu();let appItem=NSMenuItem();appItem.submenu=app;root.addItem(appItem)
        item(app,"Open Meeting Notes",#selector(openAction));item(app,"Settings…",#selector(settingsAction),",");app.addItem(.separator());item(app,"Quit Meeting Notes",#selector(quitAction),"q")
        let recording=NSMenu(title:"Recording");let recordingItem=NSMenuItem(title:"Recording",action:nil,keyEquivalent:"");recordingItem.submenu=recording;root.addItem(recordingItem)
        item(recording,"Start recording",#selector(startAction),"r");item(recording,"Stop recording",#selector(stopAction),"s");item(recording,"In-person mode",#selector(micMode));item(recording,"Online mode",#selector(callMode))
        let edit=NSMenu(title:"Edit");let editItem=NSMenuItem(title:"Edit",action:nil,keyEquivalent:"");editItem.submenu=edit;root.addItem(editItem)
        for (title,selector,key) in [("Undo","undo:","z"),("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {edit.addItem(withTitle:title,action:Selector(selector),keyEquivalent:key)}
        NSApp.mainMenu=root
    }
    private func captureCheck() async {
        let previous=store.preferences
        let call=CommandLine.arguments.contains("--online")
        store.preferences.mode=call ? .call:.microphone
        store.preferences.autoTranscribe=false
        await store.beginRecording()
        guard let id=store.activeID else{store.preferences=previous;return}
        store.update(id){$0.title="Recording check · "+(call ? "online":"in person")}
        var sound:AVAudioPlayer?
        if let i=CommandLine.arguments.firstIndex(of:"--test-speech"),CommandLine.arguments.count>i+1 {
            sound=try? AVAudioPlayer(contentsOf:URL(fileURLWithPath:CommandLine.arguments[i+1]));sound?.play()
        }
        let captureMode=store.meetings.first{$0.id==id}?.mode
        store.toggleMode()
        let modeUnchanged=store.meetings.first{$0.id==id}?.mode==captureMode
        try? await Task.sleep(for:.seconds(10));sound?.stop();store.stopRecording();store.preferences=previous
        store.savePreferences(previous)
        var report:[String:Any] = ["id":id,"mode":call ? "online":"in-person","modeUnchangedDuringCapture":modeUnchanged]
        for track in call ? ["mic","system"]:["mic"] {
            if let audio=try? AVAudioFile(forReading:store.database.folder(id).appendingPathComponent(track+".caf")) {
                report[track+"Seconds"]=Double(audio.length)/audio.fileFormat.sampleRate
            }
        }
        report["captureError"]=store.meetings.first{$0.id==id}?.error ?? ""
        if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:URL(fileURLWithPath:"/tmp/meetingnotes-capture-\(call ? "online":"mic").json"))}
        if CommandLine.arguments.contains("--exit-after-check"){NSApp.terminate(nil)}
    }
}

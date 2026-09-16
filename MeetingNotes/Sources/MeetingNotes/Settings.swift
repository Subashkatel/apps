import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LocalSupport
import ServiceManagement

struct MeetingSettings:View {
    @ObservedObject var store:MeetingStore
    @Environment(\.dismiss) private var dismiss
    @State private var prefs:Preferences
    @State private var key=""
    @State private var changeKey=false
    @State private var message=""
    @State private var checkingAI=false
    @State private var connectionMessage=""
    init(store:MeetingStore){self.store=store;_prefs=State(initialValue:store.preferences)}
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            HStack{Text("Settings").font(.custom("Georgia",size:25));Spacer();Button("Cancel"){dismiss()}.keyboardShortcut(.cancelAction);Button("Done"){save()}.keyboardShortcut(.defaultAction)}
            ScrollView{VStack(alignment:.leading,spacing:24){
                GroupBox("Recording") {VStack(alignment:.leading,spacing:12){
                    Picker("Default mode",selection:$prefs.mode){ForEach(CaptureMode.allCases){Text($0.title).tag($0)}}
                    Picker("Default project",selection:Binding(get:{prefs.preferredProject ?? ""},set:{prefs.preferredProject=$0.isEmpty ? nil:$0})){Text("Unfiled").tag("");ForEach(store.projects){Text($0.name).tag($0.id)}}
                    Toggle("Animate the mouth with microphone volume",isOn:$prefs.animateBear)
                    Toggle("Echo cancellation for meetings through speakers",isOn:$prefs.echoCancellation)
                    Text("Bear: in person. Chicken: online. Online mode captures all system audio. Headphones avoid duplicate speech across tracks; echo cancellation can change playback volume.").font(.caption).foregroundStyle(.secondary)
                }.padding(8)}
                GroupBox("Keyboard & appearance") {VStack(alignment:.leading,spacing:12){
                    Toggle("Enable global shortcuts",isOn:$prefs.globalShortcuts)
                    Text("⌃⌥R  Start / stop · ⌃⌥M  Switch mode\n⌃⌥⌘S  Stop only\n⌘R  Start · ⌘S  Stop (inside Meeting Notes)").font(.callout)
                    Text("Mode changes during recording apply to the next recording. A shortcut already claimed by another app is reported instead of silently ignored.").font(.caption).foregroundStyle(.secondary)
                    Picker("Appearance",selection:$prefs.appearance){Text("Dark").tag("dark");Text("Light").tag("light")}
                    Button(SMAppService.mainApp.status == .enabled ? "Disable open at login":"Open Meeting Notes at login"){
                        do{if SMAppService.mainApp.status == .enabled {try SMAppService.mainApp.unregister()}else{try SMAppService.mainApp.register()};message="Login setting updated."}catch{message=error.localizedDescription}
                    }
                }.padding(8)}
                GroupBox("Local transcription") {VStack(alignment:.leading,spacing:12){
                    Toggle("Transcribe automatically after recording",isOn:$prefs.autoTranscribe)
                    HStack{TextField("whisper-cli path · auto-detected when blank",text:$prefs.whisperPath);Button("Choose…"){choose{prefs.whisperPath=$0.path}}}
                    HStack{TextField("Model path · reuse VoiceBridge model when blank",text:$prefs.modelPath);Button("Choose…"){choose{prefs.modelPath=$0.path}}}
                    Picker("Language",selection:$prefs.language){Text("English").tag("en");Text("Auto-detect (multilingual model)").tag("auto");Text("Spanish").tag("es");Text("French").tag("fr");Text("German").tag("de");Text("Hindi").tag("hi");Text("Japanese").tag("ja")}
                    Text(prefs.whisper == nil ? "Whisper executable not found." : FileManager.default.isReadableFile(atPath:prefs.model.path) ? "Local transcription is ready. Model: \(prefs.model.lastPathComponent)":"Choose a Whisper model before transcribing.").font(.caption).foregroundStyle(.secondary)
                    Text("English-only models end in .en.bin. Audio never goes to an AI provider for transcription. Existing recordings can be retried.").font(.caption).foregroundStyle(.secondary)
                }.padding(8)}
                GroupBox("AI summaries") {VStack(alignment:.leading,spacing:12){
                    Picker("Provider",selection:$prefs.ai.provider){ForEach(AIProvider.allCases){Text($0.title).tag($0)}}
                    AIModelPicker(settings:prefs.ai,model:model)
                    Text("Selected: "+prefs.ai.selectionLabel).font(.caption).foregroundStyle(.secondary)
                    Text("Changes apply to your next summary after Done. Check connection sends only a test phrase.").font(.caption).foregroundStyle(.secondary)
                    HStack{Button(checkingAI ? "Checking…":"Check connection"){Task{await checkAI()}}.disabled(checkingAI);if !connectionMessage.isEmpty{Text(connectionMessage).font(.caption).textSelection(.enabled)}}
                    if prefs.ai.provider == .server {
                        TextField("API base URL, e.g. http://127.0.0.1:1234/v1",text:$prefs.ai.endpoint)
                        Toggle("Set or replace API key",isOn:$changeKey)
                        if changeKey{SecureField("API key · blank removes the saved key",text:$key)}
                    }else{
                        HStack{TextField("Executable path · auto-detect when blank",text:executable);Button("Choose…"){choose{executable.wrappedValue=$0.path}}}
                        Button("Sign in…"){do{try prefs.ai.openLogin()}catch{message=error.localizedDescription}}
                    }
                    Text("Summary defaults apply when you summarize. Each discussion has its own model selector. Recording is independent of AI; an automatic CLI default does not identify an exact model.").font(.caption).foregroundStyle(.secondary)
                    Text("Writing preferences").font(.caption)
                    TextEditor(text:$prefs.style).frame(height:85)
                    DisclosureGroup("An example in my voice · optional"){TextEditor(text:$prefs.example).frame(height:85)}
                }.padding(8)}
                GroupBox("Storage & recovery") {VStack(alignment:.leading,spacing:10){
                    Text("Original audio and transcripts are retained. Moving a meeting to Trash never deletes its audio. Meeting notes, transcripts and recovery metadata also have separate files alongside the recording.").font(.callout)
                    Text(store.database.root.path).font(.caption).textSelection(.enabled)
                    HStack{Button("Open data folder"){NSWorkspace.shared.open(store.database.root)};Button("Back up database now"){do{try store.database.backup(force:true);message="Database backup is available in the Backups folder. Audio remains in Recordings."}catch{message=error.localizedDescription}}}
                    Text("Local backups protect against app/data mistakes, not disk failure. Include this folder in your Mac backup. Audio is PCM and can use about 1 GB per hour in online mode.").font(.caption).foregroundStyle(.secondary)
                }.padding(8)}
            }}
            if !message.isEmpty{Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
        }.padding(24).frame(width:670,height:700)
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
        .preferredColorScheme(prefs.appearance == "light" ? .light:.dark)
        .onChange(of:prefs.ai){_,_ in connectionMessage=""}
    }
    private var model:Binding<String>{Binding(get:{prefs.ai.model},set:{switch prefs.ai.provider{case .claude:prefs.ai.claudeModel=$0;case .codex:prefs.ai.codexModel=$0;case .gemini:prefs.ai.geminiModel=$0;case .server:prefs.ai.serverModel=$0}})}
    private var executable:Binding<String>{Binding(get:{switch prefs.ai.provider{case .claude:prefs.ai.executablePath;case .codex:prefs.ai.codexExecutablePath;case .gemini:prefs.ai.geminiExecutablePath ?? "";case .server:""}},set:{switch prefs.ai.provider{case .claude:prefs.ai.executablePath=$0;case .codex:prefs.ai.codexExecutablePath=$0;case .gemini:prefs.ai.geminiExecutablePath=$0;case .server:break}})}
    private func choose(_ receive:(URL)->Void){let p=NSOpenPanel();p.canChooseDirectories=false;p.allowsMultipleSelection=false;if p.runModal() == .OK,let u=p.url{receive(u)}}
    @MainActor private func checkAI() async {
        guard !checkingAI else{return};checkingAI=true;connectionMessage="";defer{checkingAI=false}
        let config=prefs.ai
        do{let answer = try await Task.detached{try AIClient.ask("Reply with exactly CONNECTION_OK. Do not use tools.",settings:config,timeout:60)}.value;guard answer.contains("CONNECTION_OK") else{throw MeetingError("The provider replied but did not complete the connection check.")};if prefs.ai==config{connectionMessage="Connected · "+config.selectionLabel}}
        catch{if prefs.ai==config{connectionMessage=error.localizedDescription}}
    }
    private func save(){do{if changeKey{try AIKeychain.save(key,for:prefs.ai.serverURL())};store.savePreferences(prefs);if store.error == nil{dismiss()}}catch{message=error.localizedDescription}}
}

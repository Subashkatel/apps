import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CalendarSheet:View {
    @State var draft:CalendarDraft
    @ObservedObject var store:MeetingStore
    @Environment(\.dismiss) private var dismiss
    @State private var destination="apple"
    @State private var error:String?
    @State private var opening=false
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("Add to calendar").font(.custom("Georgia",size:25))
                    Text(draft.source+" · Calendar copy").font(.caption).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button{dismiss()}label:{Image(systemName:"xmark")}.buttonStyle(.plain).help("Close").accessibilityLabel("Close calendar form").disabled(opening)
            }
            TextField("Event title",text:$draft.title,axis:.vertical).font(.system(size:16,weight:.medium)).textFieldStyle(.plain).lineLimit(1...3)
                .padding(12).background(Palette.panel,in:RoundedRectangle(cornerRadius:8)).accessibilityIdentifier("calendar.title")
            Picker("Calendar",selection:$destination) {
                Text("Apple Calendar").tag("apple");Text("Google Calendar").tag("google")
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("calendar.destination")
            VStack(alignment:.leading,spacing:12) {
                if draft.needsDate {
                    Toggle("Choose a date",isOn:$draft.dateConfirmed).toggleStyle(.checkbox)
                    if !draft.dateConfirmed {Text("This task has no valid due date. Choose when to put it on your calendar.").font(.caption).foregroundStyle(Palette.secondary)}
                }
                if draft.dateConfirmed {
                    Toggle("All day",isOn:$draft.allDay).toggleStyle(.checkbox)
                    DatePicker("Starts",selection:$draft.start,displayedComponents:draft.allDay ? [.date]:[.date,.hourAndMinute])
                    DatePicker("Ends",selection:$draft.end,displayedComponents:draft.allDay ? [.date]:[.date,.hourAndMinute])
                    if !draft.allDay {Text("Time zone: "+draft.timeZone.identifier).font(.caption).foregroundStyle(Palette.secondary)}
                }
            }.onChange(of:draft.start){old,new in draft.end=draft.end.addingTimeInterval(new.timeIntervalSince(old))}
                .onChange(of:draft.allDay){_,allDay in if !allDay && draft.end<=draft.start{draft.end=draft.start.addingTimeInterval(1800)}}
            DisclosureGroup("Details (optional)") {
                TextEditor(text:$draft.details).font(.system(size:13)).scrollContentBackground(.hidden)
                    .padding(8).frame(height:100).background(Palette.panel,in:RoundedRectangle(cornerRadius:6)).accessibilityLabel("Calendar event details")
            }.font(.system(size:13))
            Text(destination == "google" ? "Opens a Google Calendar draft with this title, time and details. Save it there to add the event. Later edits won’t sync." : "Adds a calendar copy using Apple Calendar. Apple may use your default calendar or ask you to choose one. Later edits won’t sync.")
                .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal:false,vertical:true)
            if let message=error ?? (draft.dateConfirmed ? draft.validation:nil) {Text(message).font(.callout).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)}
            HStack {
                Button("Export .ics…"){exportFile()}.buttonStyle(.plain).foregroundStyle(Palette.secondary).disabled(draft.validation != nil || opening)
                Spacer()
                Button("Cancel"){dismiss()}.keyboardShortcut(.cancelAction).disabled(opening)
                Button(opening ? "Opening…":(destination == "google" ? "Open Google Calendar":"Add to Apple Calendar")){openCalendar()}
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(draft.validation != nil || opening).accessibilityIdentifier("calendar.open")
            }
        }.padding(28).frame(width:480).background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent).disabled(opening).interactiveDismissDisabled(opening)
    }
    private func exportFile() {
        let panel=NSSavePanel();panel.allowedContentTypes=[UTType(filenameExtension:"ics") ?? .data];panel.nameFieldStringValue="Meeting Notes event.ics"
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try draft.ics().write(to:url,options:.atomic);store.status="Calendar file saved. Import it into your calendar to add the event.";dismiss()}catch{self.error=error.localizedDescription}
    }
    private func openCalendar() {
        error=nil
        do {
            if destination == "google" {
                guard NSWorkspace.shared.open(try draft.googleURL()) else{throw MeetingError("Google Calendar could not open. Try again or export an .ics file.")}
                store.status="Google Calendar draft opened. Save the event there to finish adding it.";dismiss()
            } else {
                guard let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.iCal") else{throw MeetingError("Apple Calendar is unavailable. Use Google Calendar or export an .ics file.")}
                let folder=FileManager.default.temporaryDirectory.appendingPathComponent("meetingnotes-calendar",isDirectory:true)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let file=folder.appendingPathComponent(draft.id+".ics")
                try draft.ics().write(to:file,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
                opening=true
                NSWorkspace.shared.open([file],withApplicationAt:app,configuration:NSWorkspace.OpenConfiguration()){_,failure in
                    Task{@MainActor in
                        opening=false
                        if let failure{self.error="Apple Calendar could not open: "+failure.localizedDescription+" You can export an .ics file instead."}
                        else{store.status="Event sent to Apple Calendar. Check it there and finish any import prompt.";dismiss()}
                    }
                }
            }
        } catch {self.error=error.localizedDescription;opening=false}
    }
}

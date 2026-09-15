import Foundation
import AppKit
import SwiftUI

struct MeetingAttachment:Codable,Identifiable,Equatable {
    var id=UUID().uuidString
    var name:String
    var storedName:String
    var added=Date()
    var bytes:Int64
}
extension Database {
    func importAttachment(_ source:URL,meetingID:String)throws->MeetingAttachment {
        let access=source.startAccessingSecurityScopedResource();defer{if access{source.stopAccessingSecurityScopedResource()}}
        let values=try source.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard values.isRegularFile==true else{throw MeetingError("Choose a file, rather than a folder or application.")}
        let id=UUID().uuidString
        let ext=source.pathExtension.filter{$0.isLetter || $0.isNumber}.prefix(16)
        let filename=id+(ext.isEmpty ? "":"."+ext)
        let directory=folder(meetingID).appendingPathComponent("Attachments",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let target=directory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at:source,to:target)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
        return MeetingAttachment(id:id,name:source.lastPathComponent,storedName:filename,bytes:Int64(values.fileSize ?? 0))
    }
    func attachmentURL(_ attachment:MeetingAttachment,meetingID:String)->URL? {
        guard attachment.storedName==URL(fileURLWithPath:attachment.storedName).lastPathComponent,!attachment.storedName.hasPrefix(".") else{return nil}
        return folder(meetingID).appendingPathComponent("Attachments").appendingPathComponent(attachment.storedName)
    }
}
extension MeetingStore {
    func attachFiles(_ id:String) {
        let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.canChooseFiles=true;panel.allowsMultipleSelection=true;panel.prompt="Attach copies"
        guard panel.runModal() == .OK else{return}
        for url in panel.urls {
            do {
                let file=try database.importAttachment(url,meetingID:id)
                update(id){if $0.attachments==nil{$0.attachments=[]};$0.attachments?.append(file)}
                if let m=meetings.first(where:{$0.id==id}){try database.archive(m)}
            }catch{report(error);break}
        }
    }
    func openAttachment(_ file:MeetingAttachment,meetingID:String) {
        guard let url=database.attachmentURL(file,meetingID:meetingID),FileManager.default.fileExists(atPath:url.path) else{error="The attachment could not be found. Check the meeting's saved folder.";return}
        if !NSWorkspace.shared.open(url){error="macOS could not open this attachment. Use Show in Finder to choose an application."}
    }
}
struct AttachmentList:View {
    @ObservedObject var store:MeetingStore
    let meeting:Meeting
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{Text("Attachments").fontWeight(.medium);Spacer();Button("Attach files…"){store.attachFiles(meeting.id)}.buttonStyle(.plain).foregroundStyle(Palette.accent)}
            if !(meeting.attachments ?? []).isEmpty {
                ForEach(meeting.attachments ?? []){file in
                    HStack(spacing:10){
                        Image(systemName:file.name.lowercased().hasSuffix(".pdf") ? "doc.richtext":"doc")
                        Button(file.name){store.openAttachment(file,meetingID:meeting.id)}.buttonStyle(.plain).lineLimit(2)
                        Spacer();Text(ByteCountFormatter.string(fromByteCount:file.bytes,countStyle:.file)).font(.caption).foregroundStyle(Palette.secondary)
                        Menu{Button("Show in Finder"){if let url=store.database.attachmentURL(file,meetingID:meeting.id){NSWorkspace.shared.activateFileViewerSelecting([url])}};Button("Remove from meeting"){store.update(meeting.id){$0.attachments?.removeAll{$0.id==file.id}}}}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width:32)
                    }
                }
                Text("Local copies · attachment contents are not sent to AI").font(.caption).foregroundStyle(Palette.secondary)
            }
        }
    }
}

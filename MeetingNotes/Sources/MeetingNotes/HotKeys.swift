import AppKit
import Carbon.HIToolbox

final class MeetingHotKey {
    private static var handlers:[UInt32:()->Void]=[:]
    private static var serial:UInt32=0
    private static var installed=false
    private var reference:EventHotKeyRef?
    private let id:UInt32
    init(key:Int,modifiers:Int,action:@escaping()->Void) throws {
        if !Self.installed {
            var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
            let status=InstallEventHandler(GetApplicationEventTarget(),{_,event,_ in
                var keyID=EventHotKeyID()
                let result=GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&keyID)
                guard result == noErr,keyID.signature==OSType(0x4D4E4F54) else{return result}
                DispatchQueue.main.async{MeetingHotKey.handlers[keyID.id]?()};return noErr
            },1,&spec,nil,nil)
            guard status==noErr else{throw MeetingError("Could not install global keyboard shortcuts (\(status)).")};Self.installed=true
        }
        Self.serial+=1;id=Self.serial
        let result=RegisterEventHotKey(UInt32(key),UInt32(modifiers),EventHotKeyID(signature:OSType(0x4D4E4F54),id:id),GetApplicationEventTarget(),0,&reference)
        guard result==noErr else{throw MeetingError("A recording shortcut is already in use (\(result)). Use the bear or change the other app's shortcut; global shortcuts can be disabled in Settings.")}
        Self.handlers[id]=action
    }
    deinit{if let reference{UnregisterEventHotKey(reference)};Self.handlers[id]=nil}
}

import Foundation
import IOKit.pwr_mgt

/// Prevent idle system sleep only for the lifetime of an active recording.
/// Display sleep and deliberate sleep/lid closure remain under macOS control.
final class RecordingWakeLock {
    private var assertion:IOPMAssertionID?
    func start()throws {
        guard assertion == nil else{return}
        var id:IOPMAssertionID=0
        let result=IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,IOPMAssertionLevel(kIOPMAssertionLevelOn),"Meeting Notes recording" as CFString,&id)
        guard result==kIOReturnSuccess else{throw MeetingError("Could not keep the Mac awake for recording (\(result)). Try starting again.")}
        assertion=id
    }
    func stop(){if let assertion{IOPMAssertionRelease(assertion)};assertion=nil}
    deinit{stop()}
}

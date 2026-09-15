import Foundation

/// Owned Whisper children are terminated when the app quits. The queued meeting
/// stays on disk and resumes on next launch, without leaving a second worker.
final class TranscriptionProcess: @unchecked Sendable {
    static let shared=TranscriptionProcess()
    private let lock=NSLock()
    private var running:[UUID:Process]=[:]
    private var stopping=false
    func cancelAll(){
        lock.lock();stopping=true;let children=Array(running.values);lock.unlock()
        for child in children where child.isRunning {stop(child)}
    }
    private func stop(_ process:Process){
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline:.now()+1){if process.isRunning{kill(process.processIdentifier,SIGKILL)}}
    }
    func run(_ executable:URL,arguments:[String],directory:URL,timeout:TimeInterval)throws {
        let process=Process(),id=UUID()
        process.executableURL=executable;process.arguments=arguments;process.currentDirectoryURL=directory
        process.standardInput=FileHandle.nullDevice
        let output=Pipe();process.standardOutput=output;process.standardError=output
        lock.lock()
        guard !stopping else {lock.unlock();throw MeetingError("Transcription stopped; it will resume when you reopen Meeting Notes.")}
        do {try process.run();running[id]=process;lock.unlock()} catch {lock.unlock();throw error}
        defer {lock.lock();running[id]=nil;lock.unlock()}
        let drain=DispatchGroup()
        DispatchQueue.global().async(group:drain){while let data=try? output.fileHandleForReading.read(upToCount:32768),!data.isEmpty {}}
        let deadline=Date().addingTimeInterval(timeout)
        while process.isRunning && Date()<deadline {Thread.sleep(forTimeInterval:0.05)}
        let timedOut=process.isRunning
        if timedOut {stop(process)}
        process.waitUntilExit()
        _=drain.wait(timeout:.now()+2)
        guard !timedOut else {throw MeetingError("Transcription timed out. Try a smaller Whisper model; the original audio is saved.")}
        guard process.terminationStatus==0 else {throw MeetingError("Whisper could not finish (status \(process.terminationStatus)). Check the model and language, then retry. Original audio is saved.")}
    }
}

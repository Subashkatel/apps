import Foundation
import AVFoundation
import LocalSupport

struct AudioChunk {
    var url: URL
    var offset: Double
    var peak: Float
}
enum Transcription {
    /// Convert incrementally and split into ten-minute mono chunks. Both memory
    /// and whisper context stay bounded even for long meetings.
    static func chunks(source: URL, directory: URL) throws -> [AudioChunk] {
        let input = try AVAudioFile(forReading: source)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input.processingFormat, to: outputFormat),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else { throw MeetingError("This recording's audio format could not be converted.") }
        var current: AVAudioFile?; var result: [AudioChunk] = []; var total: Int64 = 0
        var readError: Error?
        while true {
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { count, status in
                if input.framePosition >= input.length { status.pointee = .endOfStream; return nil }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: max(4096,count)) else { status.pointee = .endOfStream; readError = MeetingError("Could not allocate a transcription buffer."); return nil }
                do { try input.read(into: buffer); status.pointee = buffer.frameLength > 0 ? .haveData : .endOfStream; return buffer }
                catch { readError = error; status.pointee = .endOfStream; return nil }
            }
            if let error = readError ?? conversionError { throw error }
            if output.frameLength > 0 {
                if current == nil || current!.length >= 16000*600 {
                    let url = directory.appendingPathComponent("chunk-\(result.count).wav")
                    current = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:16000,AVNumberOfChannelsKey:1,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false],commonFormat:.pcmFormatFloat32,interleaved:false)
                    result.append(AudioChunk(url:url,offset:Double(total)/16000,peak:0))
                }
                if let values = output.floatChannelData?[0] { for n in 0..<Int(output.frameLength) { result[result.count-1].peak = max(result[result.count-1].peak,abs(values[n])) } }
                try current?.write(from: output); total += Int64(output.frameLength)
            }
            if status == .endOfStream { break }
            if status == .error { throw MeetingError("Audio conversion failed.") }
        }
        current = nil
        return result
    }
    static func parse(_ data: Data, track: String, offset: Double, prefix: String) throws -> [Segment] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String:Any], let entries = json["transcription"] as? [[String:Any]] else { throw MeetingError("Whisper returned an unreadable transcript. The audio is still saved.") }
        return try entries.enumerated().compactMap { index, entry in
            guard let text = entry["text"] as? String, let offsets = entry["offsets"] as? [String:Any], let from = offsets["from"] as? Double, let to = offsets["to"] as? Double, from.isFinite, to.isFinite, from>=0, to>=from else { throw MeetingError("Whisper returned invalid timestamps.") }
            let clean = text.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !clean.isEmpty, !clean.hasPrefix("[BLANK_AUDIO]"), clean != "[Silence]" else { return nil }
            return Segment(id:prefix+"-\(index)",track:track,start:offset+from/1000,end:offset+to/1000,text:clean)
        }
    }
    static func run(meeting: Meeting, folder: URL, preferences: Preferences, progress: @escaping (String)->Void) throws -> [Segment] {
        guard let cli = preferences.whisper else { throw MeetingError("Whisper is not available. Choose whisper-cli in Settings.") }
        guard FileManager.default.isReadableFile(atPath:preferences.model.path) else { throw MeetingError("Choose a local Whisper model in Settings. Your recording is safe and can be retried.") }
        let temp = folder.appendingPathComponent("transcription-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:temp) }
        var result: [Segment] = []
        let tracks = meeting.mode == .call ? ["mic","system"] : ["mic"]
        guard tracks.contains(where:{FileManager.default.fileExists(atPath:folder.appendingPathComponent($0+".caf").path)}) else { throw MeetingError("No audio file was captured. Your written notes are preserved.") }
        for track in tracks {
            let source = folder.appendingPathComponent(track+".caf")
            guard FileManager.default.fileExists(atPath:source.path) else {
                if meeting.captureIssue != nil || meeting.phase == .interrupted { continue }
                throw MeetingError("The \(track) recording is missing. The other files have been preserved.")
            }
            progress("Preparing \(track == "mic" ? "microphone" : "system audio")…")
            let trackDir = temp.appendingPathComponent(track);try FileManager.default.createDirectory(at:trackDir,withIntermediateDirectories:true)
            let chunks = try chunks(source:source,directory:trackDir)
            for (index,chunk) in chunks.enumerated() {
                if chunk.peak < 0.00001 { continue }
                progress("Transcribing \(track == "mic" ? "microphone" : "system audio") · \(index+1) of \(chunks.count)")
                let output = chunk.url.deletingPathExtension().appendingPathExtension("result")
                try TranscriptionProcess.shared.run(cli,arguments:["-m",preferences.model.path,"-f",chunk.url.path,"-l",preferences.language,"-oj","-of",output.path,"-np","-t","4"],directory:temp,timeout:1800)
                result += try parse(Data(contentsOf:output.appendingPathExtension("json")),track:track,offset:chunk.offset+(meeting.offsets[track] ?? 0),prefix:meeting.id+"-"+track+"-\(index)")
            }
        }
        return result.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}

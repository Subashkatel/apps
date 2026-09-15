import AVFoundation
import Foundation

/// Copy the borrowed audio buffer, then write on a bounded serial queue.
/// Capture errors and live levels are read under a lock by the main-thread meter.
final class AudioSink: @unchecked Sendable {
    struct Health { var first: Date?; var last: Date?; var frames: Int64 = 0; var rms: Float = 0; var error: String? }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "local.meetingnotes.audio-write", qos: .userInitiated)
    private var file: AVAudioFile?
    private var health = Health()
    private var pending = 0
    private var closed = false
    init(url: URL, format: AVAudioFormat) throws {
        // PCM CAF remains readable after an interrupted process, without an AAC
        // finalization dependency. No entire-meeting buffer is kept in memory.
        file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey:kAudioFormatLinearPCM, AVSampleRateKey:format.sampleRate, AVNumberOfChannelsKey:format.channelCount, AVLinearPCMBitDepthKey:16, AVLinearPCMIsFloatKey:false, AVLinearPCMIsBigEndianKey:false], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }
    var snapshot: Health { lock.lock(); defer { lock.unlock() }; return health }
    func append(_ source: AVAudioPCMBuffer) {
        lock.lock()
        guard !closed, health.error == nil else { lock.unlock(); return }
        guard pending < 48 else { health.error = "The disk could not keep up with recording. Audio already written is retained."; lock.unlock(); return }
        pending += 1; lock.unlock()
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { fail("Could not allocate an audio buffer."); return }
        copy.frameLength = source.frameLength
        let from = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for i in 0..<min(from.count,to.count) {
            if let dest = to[i].mData, let src = from[i].mData { memcpy(dest,src,Int(from[i].mDataByteSize)); to[i].mDataByteSize = from[i].mDataByteSize }
        }
        let timestamp = Date()
        var sum: Double = 0; var samples = 0
        if let channels = copy.floatChannelData {
            let count = Int(copy.frameLength) * (copy.format.isInterleaved ? Int(copy.format.channelCount) : 1)
            for i in 0..<count { let v = Double(channels[0][i]); sum += v*v }; samples = count
        }
        let rms = samples > 0 ? Float(sqrt(sum/Double(samples))) : 0
        queue.async { [self] in
            do {
                try file?.write(from: copy)
                lock.lock(); health.first = health.first ?? timestamp; health.last = timestamp; health.frames += Int64(copy.frameLength); health.rms = rms; pending -= 1; lock.unlock()
            } catch { fail("Audio could not be written: " + error.localizedDescription) }
        }
    }
    private func fail(_ message: String) { lock.lock(); health.error = health.error ?? message; pending = max(0,pending-1); lock.unlock() }
    func close() { lock.lock(); closed = true; lock.unlock(); queue.sync { file = nil } }
    func flushWrites() { queue.sync {} }
}

final class MicrophoneRecorder {
    private var engine: AVAudioEngine?
    private(set) var sink: AudioSink?
    func start(url: URL, echoCancellation: Bool) throws {
        let engine = AVAudioEngine(); let input = engine.inputNode
        if echoCancellation { try input.setVoiceProcessingEnabled(true) }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MeetingError("No microphone is available. Connect an input device and try again.") }
        let sink = try AudioSink(url: url, format: format)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in sink.append(buffer) }
        do { engine.prepare(); try engine.start(); self.engine = engine; self.sink = sink }
        catch { input.removeTap(onBus: 0); sink.close(); throw error }
    }
    func stop() { engine?.stop(); engine?.inputNode.removeTap(onBus: 0); sink?.close(); engine = nil }
}

@MainActor final class CaptureSession {
    let id: String
    let started = Date()
    let mode: CaptureMode
    let microphone = MicrophoneRecorder()
    let system = SystemAudioRecorder()
    private let wakeLock=RecordingWakeLock()
    init(id: String, mode: CaptureMode) { self.id = id; self.mode = mode }
    func start(folder: URL, echoCancellation: Bool) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
        do {
            try wakeLock.start()
            if mode == .call { try system.start(writingTo: folder.appendingPathComponent("system.caf")) }
            try microphone.start(url: folder.appendingPathComponent("mic.caf"), echoCancellation: echoCancellation)
        } catch { microphone.stop(); system.stop(); wakeLock.stop(); throw error }
    }
    func stop() -> [String: Double] {
        wakeLock.stop()
        microphone.stop(); system.stop()
        var offsets: [String: Double] = [:]
        if let first = microphone.sink?.snapshot.first { offsets["mic"] = max(0,first.timeIntervalSince(started)) }
        if let first = system.sink?.snapshot.first { offsets["system"] = max(0,first.timeIntervalSince(started)) }
        return offsets
    }
    var error: String? {
        if let error = microphone.sink?.snapshot.error ?? system.sink?.snapshot.error { return error }
        if Date().timeIntervalSince(started) > 5 {
            if let last = microphone.sink?.snapshot.last { if Date().timeIntervalSince(last)>4 { return "The microphone stopped delivering audio. Check your input device." } }
            else { return "No microphone audio arrived. Check microphone permission and the selected input device." }
            if mode == .call, system.sink?.snapshot.first == nil { return "No system-audio buffers arrived. Check System Audio Recording permission." }
            if mode == .call, let last = system.sink?.snapshot.last, Date().timeIntervalSince(last)>4 { return "System audio stopped arriving. Check the audio device and System Audio Recording permission." }
        }
        return nil
    }
    var mouthLevel: CGFloat {
        guard let h = microphone.sink?.snapshot, let last = h.last, Date().timeIntervalSince(last)<0.5 else { return 0 }
        let db = 20*log10(max(h.rms,0.000001))
        return CGFloat(max(0,min(1,(db+48)/30)))
    }
}

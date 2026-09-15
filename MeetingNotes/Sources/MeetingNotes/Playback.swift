import AVFoundation
import SwiftUI

@MainActor final class MeetingPlayback:ObservableObject {
    @Published private(set) var position:Double=0
    @Published private(set) var duration:Double=0
    @Published private(set) var isPlaying=false
    @Published private(set) var meetingID:String?
    @Published private(set) var track="mic"
    private var audio:AVAudioPlayer?
    private var timer:Timer?
    func open(_ url:URL,meetingID:String,track:String,at time:Double=0)throws {
        stop()
        let player=try AVAudioPlayer(contentsOf:url)
        player.prepareToPlay();audio=player;self.meetingID=meetingID;self.track=track;duration=player.duration
        seek(time);resume()
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){[weak self] _ in Task{@MainActor in self?.refresh()}}
    }
    private func refresh(){guard let audio else{return};if isPlaying && !audio.isPlaying{position=duration;isPlaying=false}else if audio.isPlaying{position=audio.currentTime}}
    func toggle(){if isPlaying{audio?.pause();isPlaying=false}else{resume()}}
    private func resume(){guard let audio else{return};if position>=duration{audio.currentTime=0;position=0};isPlaying=audio.play()}
    func seek(_ seconds:Double){guard let audio,seconds.isFinite else{return};position=max(0,min(duration,seconds));audio.currentTime=position}
    func stop(){timer?.invalidate();timer=nil;audio?.stop();audio=nil;meetingID=nil;position=0;duration=0;isPlaying=false}
}

struct PlaybackControls:View {
    @ObservedObject var playback:MeetingPlayback
    @State private var scrubbing=false
    @State private var requested:Double=0
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            HStack(spacing:12){
                Button{playback.toggle()}label:{Image(systemName:playback.isPlaying ? "pause.fill":"play.fill").frame(width:20)}.help(playback.isPlaying ? "Pause":"Play")
                Button{playback.seek(playback.position-15)}label:{Image(systemName:"gobackward.15")}.help("Back 15 seconds")
                Button{playback.seek(playback.position+15)}label:{Image(systemName:"goforward.15")}.help("Forward 15 seconds")
                Text(playback.track == "mic" ? "Microphone":"Call audio").font(.caption).foregroundStyle(Palette.secondary)
                Spacer()
                Text(Segment.timestamp(scrubbing ? requested:playback.position)+" / "+Segment.timestamp(playback.duration)).font(.caption.monospacedDigit()).foregroundStyle(Palette.secondary)
            }.buttonStyle(.plain)
            Slider(value:Binding(get:{scrubbing ? requested:playback.position},set:{requested=$0;if !scrubbing{playback.seek($0)}}),in:0...max(0.01,playback.duration),onEditingChanged:{editing in
                if editing{requested=playback.position;scrubbing=true}else{playback.seek(requested);scrubbing=false}
            }).accessibilityLabel("Audio playback position")
        }.padding(12).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:8))
    }
}

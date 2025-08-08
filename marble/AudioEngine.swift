import AVFoundation

final class AudioEngine {
    private var player: AVAudioPlayer?

    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if let url = Bundle.main.url(forResource: "marble", withExtension: "wav") {
                player = try AVAudioPlayer(contentsOf: url)
                player?.enableRate = true
                player?.numberOfLoops = -1
                player?.volume = 0.4
                player?.rate = 1.0
                player?.play()
            } else {
                print("marble_loop.wav missing from bundle")
            }
        } catch { print("Audio error:", error) }
    }

    func setSpeed(_ v: Double) {
        let clamped = max(0, min(1, v))
        player?.rate = Float(0.75 + clamped * 0.75)   // 0.75x–1.5x
        player?.volume = Float(0.2 + clamped * 0.6)   // 0.2–0.8
    }
}

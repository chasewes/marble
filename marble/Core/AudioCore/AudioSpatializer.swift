import AVFoundation

@MainActor
final class AudioSpatializer: ObservableObject {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    @Published var isRunning = false

    init() {
        // Listener at origin, facing -Z (default).
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)

        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 1.5
        environment.distanceAttenuationParameters.rolloffFactor = 0.0   // ≈ no distance attenuation

        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
        environment.reverbParameters.level = -10

        
        // A touch of reverb helps externalization (optional).
//        environment.reverbParameters.enable = true
//        environment.reverbParameters.level = -12

        engine.attach(environment)
        engine.attach(player)

        // IMPORTANT: connect the player to the environment with a MONO format.
        let sr = AVAudioSession.sharedInstance().sampleRate > 0
               ? AVAudioSession.sharedInstance().sampleRate
               : 48_000
        let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        engine.connect(player, to: environment, format: mono)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)

        // Binauralize the player (the source).
        player.renderingAlgorithm = .HRTF
        player.volume = 0.2
    }

    func start(frequencyHz: Double = 440) {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()

            // Keep it simple: .playback with no Bluetooth/AirPlay flags.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])

            // Build a looping mono tone buffer at the current hardware rate.
            let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
            buffer = makeSineBuffer(freq: frequencyHz, seconds: 1.0, sr: sr, gain: 0.18)

            engine.prepare()
            try engine.start()

            if let buf = buffer {
                player.scheduleBuffer(buf, at: nil, options: [.loops], completionHandler: nil)
                player.play()
            }

            isRunning = true
            logRoute("Started")
            observeRouteChanges()

        } catch {
            print("AudioSpatializer.start() error: \(error)")
            // Fallback: try again with the bare minimum if we hit a param error.
            // (This handles exotic devices / OS quibbles.)
            if (error as NSError).code == -50 {
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback)
                    try AVAudioSession.sharedInstance().setActive(true)
                    try engine.start()
                    if let buf = buffer {
                        player.scheduleBuffer(buf, at: nil, options: [.loops], completionHandler: nil)
                        player.play()
                    }
                    isRunning = true
                    logRoute("Restarted with minimal session")
                } catch {
                    print("Fallback start failed: \(error)")
                }
            }
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        isRunning = false
    }

    func setVolume(_ v: Float) { player.volume = v }

    func updateListener(yaw: Double, pitch: Double, roll: Double) {
        let r2d = 180.0 / .pi
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw:   Float(yaw * r2d),
            pitch: Float(pitch * r2d),
            roll:  Float(roll * r2d)
        )
    }

    func updateSource(xMeters: Float, zMeters: Float) {
        player.position = AVAudio3DPoint(x: xMeters, y: 0, z: zMeters)
    }

    // --- Helpers ---
    private func makeSineBuffer(freq: Double, seconds: Double, sr: Double, gain: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)! // MONO
        let frames = AVAudioFrameCount(seconds * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let out = buf.floatChannelData![0]
        let w = 2.0 * Double.pi * freq / sr
        for n in 0..<Int(frames) { out[n] = Float(sin(w * Double(n))) * gain }
        return buf
    }

    private func logRoute(_ prefix: String) {
        let r = AVAudioSession.sharedInstance().currentRoute
        let outs = r.outputs.map { "\($0.portType.rawValue): \($0.portName)" }.joined(separator: ", ")
        print("\(prefix) — route: \(outs)")
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            self?.logRoute("RouteChanged")
        }
    }
    // Swap the currently playing loop with a new buffer and keep playing.
    func replaceWithLoop(_ newBuffer: AVAudioPCMBuffer) {
        if !isRunning { start() }    // uses your existing start()
        player.stop()
        buffer = newBuffer
        player.scheduleBuffer(newBuffer, at: nil, options: [.loops], completionHandler: nil)
        player.play()
    }

    // Public: play a mono tone loop (handy to switch back).
    func playTone(_ frequencyHz: Double = 440, gain: Float = 0.18) {
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let buf = makeSineBuffer(freq: frequencyHz, seconds: 1.0, sr: sr, gain: gain)
        replaceWithLoop(buf)
    }

    // Public: play a bundled audio file as a loop (auto-downmix to mono if needed).
    func playLoopedSFX(resource: String, ext: String = "wav") throws {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            throw NSError(domain: "AudioSpatializer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing \(resource).\(ext) in bundle"])
        }
        let file = try AVAudioFile(forReading: url)
        let monoBuf = try makeMonoBuffer(from: file)
        replaceWithLoop(monoBuf)
    }

    // --- Downmix helper ---
    private func makeMonoBuffer(from file: AVAudioFile) throws -> AVAudioPCMBuffer {
        let fmt = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else {
            throw NSError(domain: "AudioSpatializer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Buffer alloc failed"])
        }
        try file.read(into: inBuf)
        if fmt.channelCount == 1 {
            inBuf.frameLength = frames
            return inBuf
        }
        // Downmix N channels -> mono by averaging.
        let monoFmt = AVAudioFormat(standardFormatWithSampleRate: fmt.sampleRate, channels: 1)!
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: monoFmt, frameCapacity: frames),
              let inData = inBuf.floatChannelData,
              let outData = outBuf.floatChannelData?.pointee else {
            throw NSError(domain: "AudioSpatializer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Downmix alloc failed"])
        }
        let C = Int(fmt.channelCount)
        let N = Int(inBuf.frameLength)
        for i in 0..<N {
            var sum: Float = 0
            for c in 0..<C { sum += inData[c][i] }
            outData[i] = sum / Float(C)
        }
        outBuf.frameLength = AVAudioFrameCount(N)
        return outBuf
    }

}



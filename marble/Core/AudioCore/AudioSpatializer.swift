import AVFoundation

@MainActor
final class AudioSpatializer: ObservableObject {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)   // ⬅️ new
    private var buffer: AVAudioPCMBuffer?
    @Published var isRunning = false

    init() {
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)

        // Stronger externalization while testing
        environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
        environment.reverbParameters.level = -10
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 1.5
        environment.distanceAttenuationParameters.rolloffFactor = 0.0

        engine.attach(environment)
        engine.attach(player)
        engine.attach(eq)                                // ⬅️ attach EQ

        // MONO all the way into the environment (spatializer only works on mono)
        let sr = AVAudioSession.sharedInstance().sampleRate > 0 ? AVAudioSession.sharedInstance().sampleRate : 48_000
        let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!

        // player -> EQ -> environment -> main mixer
        engine.connect(player, to: eq, format: mono)     // ⬅️ go through EQ
        engine.connect(eq, to: environment, format: mono)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)

        // Configure EQ: band-pass ~2–8 kHz and a little presence boost
        configureEQ()

        player.renderingAlgorithm = .HRTF
        player.volume = 0.2
    }

    private func configureEQ() {
        guard eq.bands.count >= 3 else { return }
        // High-pass ~1.5 kHz
        let hp = eq.bands[0]
        hp.filterType = .highPass
        hp.frequency = 1500
        hp.bypass = false

        // Low-pass ~8 kHz
        let lp = eq.bands[1]
        lp.filterType = .lowPass
        lp.frequency = 8000
        lp.bypass = false

        // Presence bump ~7 kHz (helps front/back spectral cues)
        let peak = eq.bands[2]
        peak.filterType = .parametric
        peak.frequency = 7000
        peak.gain = 6     // dB
        peak.bandwidth = 1.0 // octaves
        peak.bypass = false
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
//    func replaceWithLoop(_ newBuffer: AVAudioPCMBuffer) {
//        if !isRunning { start() }    // uses your existing start()
//        player.stop()
//        buffer = newBuffer
//        player.scheduleBuffer(newBuffer, at: nil, options: [.loops], completionHandler: nil)
//        player.play()
//    }

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
    // Public: play AM band-passed noise as a loop
    func playNoise(gain: Float = 0.18, amHz: Double = 5.0) {
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let buf = makeAMNoiseBuffer(seconds: 2.0, sr: sr, gain: gain, amHz: amHz) // 2 s loop
        replaceWithLoop(buf)
    }

    // Swap the current loop with a new buffer and keep playing
    func replaceWithLoop(_ newBuffer: AVAudioPCMBuffer) {
        if !isRunning { try? start() }
        player.stop()
        buffer = newBuffer
        player.scheduleBuffer(newBuffer, at: nil, options: [.loops], completionHandler: nil)
        player.play()
    }

    // --- Generators ---
    private func makeAMNoiseBuffer(seconds: Double, sr: Double, gain: Float, amHz: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let frames = AVAudioFrameCount(seconds * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let out = buf.floatChannelData![0]
        let wAM = 2.0 * Double.pi * amHz / sr

        // smooth AM between ~20% and 100% to avoid clicks
        for n in 0..<Int(frames) {
            let am = 0.6 + 0.4 * sin(wAM * Double(n))  // 0.2..1.0
            let sample = Float.random(in: -1...1)      // white noise
            out[n] = sample * gain * Float(am)
        }
        return buf
    }


}



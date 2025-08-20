import AVFoundation
import CoreGraphics

final class AudioEngine {

    // MARK: - Nodes / Engine
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()

    private let rollNode = AVAudioPlayerNode()
    private let rollVarispeed = AVAudioUnitVarispeed()

    private let impactNode = AVAudioPlayerNode()
    private let whooshNode = AVAudioPlayerNode()

    // MARK: - Buffers
    private var rollBuffer: AVAudioPCMBuffer?
    private var impactBuffer: AVAudioPCMBuffer?
    private var whooshBuffer: AVAudioPCMBuffer?

    // MARK: - State
    private var lastWhooshAt: CFTimeInterval = 0
    private let whooshThreshold: Double = 0.70
    private let whooshCooldown: CFTimeInterval = 0.6
    private let metersPerScreen: Float = 2.0 // map screen width ≈ 2 meters in head-space

    private var started = false

    // MARK: - Lifecycle
    init() {
        // Nothing heavy here; full wiring happens in start() after session is ready.
    }

    func start() {
        guard !started else { return }
        started = true

        do {
            // 1) Session: use A2DP so we get stereo output with AirPods (spatial works here)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback,
                                    mode: .moviePlayback,
                                    options: [.allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true)

            // 2) Attach + connect using the *hardware* format so Core Audio doesn't guess wrong
            engine.attach(environment)

            let hwFormat = engine.outputNode.inputFormat(forBus: 0)
            engine.connect(environment, to: engine.mainMixerNode, format: hwFormat)

            // Rolling layer: rollNode -> varispeed -> environment
            engine.attach(rollNode)
            engine.attach(rollVarispeed)
            engine.connect(rollNode, to: rollVarispeed, format: nil)
            engine.connect(rollVarispeed, to: environment, format: nil)

            // Impacts + whoosh
            engine.attach(impactNode)
            engine.attach(whooshNode)
            engine.connect(impactNode, to: environment, format: nil)
            engine.connect(whooshNode, to: environment, format: nil)

            // 3) Load audio (any sane WAV/CAF will be converted to stereo float32)
            rollBuffer   = loadBuffer("roll_loop", ext: "wav", toMatch: environment)
            impactBuffer = loadBuffer("pling",      ext: "wav", toMatch: environment)
            whooshBuffer = loadBuffer("whoosh",     ext: "wav", toMatch: environment)

            // 4) Start engine
            engine.prepare()
            try engine.start()

            // 5) Start rolling loop silently; we’ll fade in with speed
            if let buf = rollBuffer {
                rollNode.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
                rollNode.volume = 0.0
                rollNode.play()
            } else {
                print("AudioEngine: roll_loop.wav missing/unreadable in bundle")
            }
        } catch {
            // If this prints -50 again, the session category/mode is still being rejected by hardware.
            print("Audio engine start error:", error)
        }
    }

    func stop() {
        guard started else { return }
        started = false
        rollNode.stop()
        impactNode.stop()
        whooshNode.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Game Hooks

    /// Call every frame with normalized speed [0,1]
    func setVelocity(_ v: Double) {
        let v = max(0, min(1, v))

        // Loudness and timbre of rolling layer
        rollNode.volume = Float(0.08 + v * 0.85)    // 0.08 .. 0.93
        rollVarispeed.rate = Float(0.60 + v * 0.90) // 0.60x .. 1.50x

        // Optional whoosh when moving fast, but not too often
        if v > whooshThreshold,
           CACurrentMediaTime() - lastWhooshAt > whooshCooldown {
            playWhoosh(intensity: Float((v - whooshThreshold) / (1 - whooshThreshold)))
            lastWhooshAt = CACurrentMediaTime()
        }
    }

    /// Back-compat alias for earlier wiring
    func setSpeed(_ v: Double) { setVelocity(v) }

    /// Call on wall hit. Pass normalized impact intensity [0,1].
    func playImpact(intensity: Float) {
        guard let buf = impactBuffer else { return }
        impactNode.volume = 0.2 + max(0, min(1, intensity)) * 0.9
        impactNode.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        impactNode.play()
    }

    /// Update the sound’s 3D position to match the ball’s screen position.
    func updatePosition(point: CGPoint, sceneSize: CGSize) {
        // Keep the listener at origin; move sources in front of listener’s head
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)

        let nx = (Float(point.x) / Float(sceneSize.width)) * 2 - 1    // [-1, 1]
        let ny = (Float(point.y) / Float(sceneSize.height)) * 2 - 1   // [-1, 1]

        let pos = AVAudio3DPoint(x: nx * (metersPerScreen / 2),
                                 y: ny * 0.3,
                                 z: 0.0)

        rollNode.position = pos
        impactNode.position = pos
        whooshNode.position = pos
    }

    // MARK: - Internals

    private func playWhoosh(intensity: Float) {
        guard let buf = whooshBuffer else { return }
        whooshNode.volume = 0.1 + max(0, min(1, intensity)) * 0.9
        whooshNode.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        whooshNode.play()
    }

    /// Loads an audio file from the bundle and converts it to a stereo, non‑interleaved float format
    /// compatible with the environment node / output hardware. Handles 16‑bit PCM WAVs etc.
    private func loadBuffer(_ name: String, ext: String, toMatch env: AVAudioEnvironmentNode) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("Missing audio file: \(name).\(ext)")
            return nil
        }

        do {
            let file = try AVAudioFile(forReading: url)

            // Desired output format: stereo float32, same sample rate as the file (or hardware if you prefer)
            let desired = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: file.processingFormat.sampleRate,
                                        channels: 2,
                                        interleaved: false)!

            // If the file is already in the desired format, read directly
            if file.processingFormat == desired {
                let buf = AVAudioPCMBuffer(pcmFormat: desired,
                                           frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buf)
                return buf
            }

            // Otherwise convert
            let converter = AVAudioConverter(from: file.processingFormat, to: desired)!
            let capacity = AVAudioFrameCount(file.length)
            let outBuffer = AVAudioPCMBuffer(pcmFormat: desired, frameCapacity: capacity)!

            try convert(file: file, with: converter, into: outBuffer)
            return outBuffer

        } catch {
            print("Failed to load buffer \(name).\(ext):", error)
            return nil
        }
    }

    private func convert(file: AVAudioFile,
                         with converter: AVAudioConverter,
                         into outBuffer: AVAudioPCMBuffer) throws {
        file.framePosition = 0

        while true {
            // Pull a chunk from the file
            let frameCount: AVAudioFrameCount = 4096
            guard let inBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                  frameCapacity: frameCount) else { break }
            try file.read(into: inBuffer)
            if inBuffer.frameLength == 0 { break }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return inBuffer
            }

            let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                             frameCapacity: inBuffer.frameCapacity)!
            let _ = converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
            if let error = error { throw error }

            // Append into the big output buffer
            let dst = outBuffer
            let dstOffset = Int(dst.frameLength)
            let srcFrames = Int(converted.frameLength)

            for ch in 0..<Int(converted.format.channelCount) {
                let srcPtr = converted.floatChannelData![ch]
                let dstPtr = dst.floatChannelData![ch] + dstOffset
                dstPtr.assign(from: srcPtr, count: srcFrames)
            }
            dst.frameLength += converted.frameLength
        }
    }
}

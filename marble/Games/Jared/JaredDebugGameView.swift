import SwiftUI

// JaredDebugGameView.swift

struct JaredDebugGameView: View {
    @EnvironmentObject var tracker: HeadTracker
    @EnvironmentObject var audio: AudioSpatializer
    private let metersPerRad: Float = 1.0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Header(title: "Jared’s Game")
                Readout(snapshot: tracker.snapshot)
                TiltDot(roll: tracker.roll, pitch: tracker.pitch, color: .red)
                Spacer(minLength: 8)
            }
            .padding()
            .monospaced()
        }
        .onAppear { try? audio.start(frequencyHz: 440) }
//        .onReceive(tracker.$snapshot) { s in
//            audio.updateListener(yaw: s.yaw, pitch: s.pitch, roll: s.roll)
//            let x = Float(s.roll) * metersPerRad
//            let z = Float(-s.pitch) * metersPerRad
//            audio.updateSource(xMeters: x, zMeters: z)
//        }
        .onReceive(tracker.$snapshot) { s in
            audio.updateListener(yaw: s.yaw, pitch: s.pitch, roll: s.roll)

            // Map head tilt to a *direction*, then fix distance to R meters.
            let dx = Float(s.roll)
            let dz = Float(-s.pitch)
            let len = max(0.001, hypotf(dx, dz))
            let R: Float = 1.5   // meters from listener
            let x = R * dx / len
            let z = R * dz / len
            audio.updateSource(xMeters: x, zMeters: z)
        }

        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Tone") { audio.playTone(440) }
                /*Button("SFX")  { try? audio.playLoopedSFX(resource: "loop_click") }*/ // add loop_click.wav to your app bundle
                Button("SFX")  { try? audio.playLoopedSFX(resource: "1000marbles") }
                Button(audio.isRunning ? "Stop" : "Play") {
                    if audio.isRunning { audio.stop() } else { try? audio.start() }
                }
            }
        }
    }
}

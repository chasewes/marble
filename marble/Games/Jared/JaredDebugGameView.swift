//
//  JaredDebugGameView.swift
//  marble
//
//  Created by Jared Marchant on 8/20/25.
//


import SwiftUI
import Combine

struct JaredDebugGameView: View {
    @EnvironmentObject var tracker: HeadTracker
    @EnvironmentObject var audio: AudioSpatializer

    // ---- Live (tracking) controls ----
    @State private var invertFB = true
    @State private var invertLR = false
    @State private var radius: Float = 1.8  // meters

    // ---- Test Mode (no tracking) ----
    @State private var testMode = true      // ⬅️ turn on/off here or via the toggle
    @State private var rpm: Double = 6      // revolutions per minute (10s per rev)
    @State private var clockwise = true
    @State private var angle: Double = 0    // radians
    private let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Header(title: "Jared’s Game")
                Readout(snapshot: tracker.snapshot)
                TiltDot(roll: tracker.roll, pitch: tracker.pitch, color: .red)

                // ---- Test Mode controls UI ----
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Test Mode (rotate source around listener)", isOn: $testMode)

                    if testMode {
                        HStack {
                            Text("Speed")
                            Slider(value: $rpm, in: 0.5...30, step: 0.5)
                            Text("\(rpm, specifier: "%.1f") RPM")
                        }
                        HStack {
                            Text("Radius")
                            Slider(value: Binding(
                                get: { Double(radius) },
                                set: { radius = Float($0) }
                            ), in: 0.5...3.0, step: 0.1)
                            Text("\(radius, specifier: "%.1f") m")
                        }
                        Toggle("Clockwise", isOn: $clockwise)
                        Text("Azimuth: \(Int((angle * 180 / .pi).truncatingRemainder(dividingBy: 360)))° (0° = front)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        // Live mapping options when NOT in test mode
                        Toggle("Invert Front/Back", isOn: $invertFB)
                        Toggle("Invert Left/Right", isOn: $invertLR)
                        HStack {
                            Text("Radius")
                            Slider(value: Binding(
                                get: { Double(radius) },
                                set: { radius = Float($0) }
                            ), in: 0.5...3.0, step: 0.1)
                            Text("\(radius, specifier: "%.1f") m")
                        }
                        Text("Live: yaw rotates listener; roll/pitch aim source.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Spacer(minLength: 8)
            }
            .padding()
            .monospaced()
        }
//        .onAppear { try? audio.start(frequencyHz: 440) }

        // ---- Animate TEST MODE (ignores tracking) ----
        .onReceive(timer) { _ in
            guard testMode else { return }
            // Freeze listener straight ahead (no head tracking)
            audio.updateListener(yaw: 0, pitch: 0, roll: 0)

            // Advance angle by RPM
            let w = rpm * 2 * .pi / 60.0              // rad/s
            angle += (clockwise ? -1 : 1) * w / 60.0  // 60 Hz timer
            angle.formTruncatingRemainder(dividingBy: 2 * .pi)

            // Convert azimuth (0° = front) to X/Z:
            // +X = right, -Z = front
            let x = radius * Float(sin(angle))
            let z = -radius * Float(cos(angle))
            audio.updateSource(xMeters: x, zMeters: z)
        }

        // ---- Live mode: use tracking (disabled when testMode == true) ----
        .onReceive(tracker.$snapshot) { s in
            guard !testMode else { return }

            // Only yaw rotates the listener (keeps front/back cues clear)
            audio.updateListener(yaw: s.yaw, pitch: 0, roll: 0)

            // Map roll/pitch to a direction; keep constant radius
            var dx = Float(s.roll)
            var dz = Float(s.pitch)    // +pitch = forward by default
            if invertLR { dx = -dx }
            if invertFB { dz = -dz }

            let len = max(0.001, hypotf(dx, dz))
            let x = radius * dx / len
            let z = radius * dz / len  // remember: -Z is "in front"; we’re handling sign above
            audio.updateSource(xMeters: x, zMeters: z)
        }

        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("Audio") {
                    Button("Tone") { audio.playTone(440) }
                    Button("SFX (loop)") { try? audio.playLoopedSFX(resource: "1000marbles") }
                }
                Button(audio.isRunning ? "Stop" : "Play") {
                    if audio.isRunning { audio.stop() } else { try? audio.start() }
                }
            }
        }
    }
}

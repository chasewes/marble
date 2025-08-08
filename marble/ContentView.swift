import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var tracker = HeadTracker()
    private let audio = AudioEngine()
    private let scene = MarbleScene(size: UIScreen.main.bounds.size)

    private let gravityScale: CGFloat = 12.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpriteView(scene: scene)
                .ignoresSafeArea()
            // Tiny HUD so you know sensors are live
            VStack(alignment: .leading) {
                Text(String(format: "Roll:  %.2f", tracker.roll))
                Text(String(format: "Pitch: %.2f", tracker.pitch))
            }
            .padding(12)
            .background(.black.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()
        }
        .onAppear {
            audio.start()
            tracker.start()
            scene.scaleMode = .resizeFill
            scene.onSpeedChange = { audio.setSpeed($0) }

            Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
                let gx = sin(tracker.roll) * gravityScale
                let gy = -sin(tracker.pitch) * gravityScale
                scene.setGravity(CGVector(dx: gx, dy: gy))
            }
        }
        .onDisappear { tracker.stop() }
    }
}

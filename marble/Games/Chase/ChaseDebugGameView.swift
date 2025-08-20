import SwiftUI


struct ChaseDebugGameView: View {
    @EnvironmentObject var tracker: HeadTracker

    var body: some View {
        ScrollView { // ← wrap
            VStack(spacing: 20) {
                Header(title: "Chase’s Game")
                Readout(snapshot: tracker.snapshot)
                TiltDot(roll: tracker.roll, pitch: tracker.pitch, color: .blue)
                Spacer(minLength: 8)
            }
            .padding()
            .monospaced()
        }
    }
}

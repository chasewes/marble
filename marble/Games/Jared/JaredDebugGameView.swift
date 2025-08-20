import SwiftUI


struct JaredDebugGameView: View {
    @EnvironmentObject var tracker: HeadTracker

    var body: some View {
        ScrollView { // ← wrap
            VStack(spacing: 20) {
                Header(title: "Jared’s Game")
                Readout(snapshot: tracker.snapshot)
                TiltDot(roll: tracker.roll, pitch: tracker.pitch, color: .red)
                Spacer(minLength: 8)
            }
            .padding()
            .monospaced()
        }
    }
}

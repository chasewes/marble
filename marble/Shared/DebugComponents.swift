import SwiftUI

struct Header: View {
    let title: String
    var body: some View {
        HStack {
            Text(title).font(.title2).bold()
            Spacer()
            ConnectionBadge()
        }
    }
}

struct ConnectionBadge: View {
    @EnvironmentObject var tracker: HeadTracker
    var body: some View {
        Label(tracker.isConnected ? "Connected" : "Not Connected",
              systemImage: tracker.isConnected ? "dot.circle.fill" : "xmark.circle")
            .foregroundStyle(tracker.isConnected ? .green : .red)
            .font(.subheadline)
    }
}

// Shows EVERYTHING from MotionSnapshot, nicely grouped
struct Readout: View {
    let snapshot: MotionSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                groupBox("Attitude (radians + degrees)") {
                    twoCol("roll",  radDeg(snapshot.roll))
                    twoCol("pitch", radDeg(snapshot.pitch))
                    twoCol("yaw",   radDeg(snapshot.yaw))
                }

                groupBox("Quaternion (x, y, z, w)") {
                    twoCol("x", fmt(snapshot.quatX))
                    twoCol("y", fmt(snapshot.quatY))
                    twoCol("z", fmt(snapshot.quatZ))
                    twoCol("w", fmt(snapshot.quatW))
                }

                groupBox("Rotation rate (rad/s)") {
                    twoCol("x", fmt(snapshot.rotX))
                    twoCol("y", fmt(snapshot.rotY))
                    twoCol("z", fmt(snapshot.rotZ))
                }

                groupBox("User acceleration (g)") {
                    twoCol("x", fmt(snapshot.accX))
                    twoCol("y", fmt(snapshot.accY))
                    twoCol("z", fmt(snapshot.accZ))
                }

                groupBox("Gravity (g)") {
                    twoCol("x", fmt(snapshot.gravX))
                    twoCol("y", fmt(snapshot.gravY))
                    twoCol("z", fmt(snapshot.gravZ))
                }

                groupBox("Meta") {
                    twoCol("timestamp", String(format: "%.3f", snapshot.timestamp))
                    twoCol("connected", snapshot.isConnected ? "true" : "false")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .monospaced()
    }

    // MARK: - Small helpers

    private func groupBox(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 4) { content() }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func twoCol(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).frame(width: 120, alignment: .leading).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func fmt(_ x: Double) -> String { String(format: "%+.4f", x) }

    private func radDeg(_ r: Double) -> String {
        let d = r * 180 / .pi
        return String(format: "%+.4f rad  (%+.2f°)", r, d)
    }
}

/// A tiny dot that moves with head tilt so you can visualize orientation quickly.
struct TiltDot: View {
    let roll: Double
    let pitch: Double
    let color: Color

    private let box: CGFloat = 220
    private let radius: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.secondary, lineWidth: 1)
                .frame(width: box, height: box)
                .overlay(alignment: .center) { Crosshair() }

            // Map angles to position inside the box
            let scale: CGFloat = 70
            let dx = CGFloat(sin(roll)) * scale
            let dy = CGFloat(-sin(pitch)) * scale

            Circle()
                .fill(color)
                .frame(width: radius * 2, height: radius * 2)
                .offset(x: dx, y: dy)
                .animation(.easeOut(duration: 0.05), value: dx)
                .animation(.easeOut(duration: 0.05), value: dy)
        }
        .frame(height: box)
        .padding(.top, 8)
    }
}

private struct Crosshair: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w/2, y: 0));   p.addLine(to: CGPoint(x: w/2, y: h))
                p.move(to: CGPoint(x: 0,   y: h/2)); p.addLine(to: CGPoint(x: w,   y: h/2))
            }
            .stroke(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [3,3]))
        }
    }
}

import CoreMotion
import Combine

// Everything we can reasonably expose from CMDeviceMotion via AirPods:
struct MotionSnapshot {
    let timestamp: TimeInterval

    // Attitude (radians)
    let roll: Double
    let pitch: Double
    let yaw: Double

    // Quaternion
    let quatX: Double
    let quatY: Double
    let quatZ: Double
    let quatW: Double

    // Gyro (radians/sec)
    let rotX: Double
    let rotY: Double
    let rotZ: Double

    // Linear acceleration (g's)
    let accX: Double
    let accY: Double
    let accZ: Double

    // Gravity vector (g's)
    let gravX: Double
    let gravY: Double
    let gravZ: Double

    // Connection convenience
    let isConnected: Bool
}

final class HeadTracker: NSObject, ObservableObject {
    private let manager = CMHeadphoneMotionManager()

    // Back-compat simple fields
    @Published var roll: Double = 0
    @Published var pitch: Double = 0
    @Published var isConnected: Bool = false

    // Full snapshot
    @Published var snapshot: MotionSnapshot = .init(
        timestamp: 0,
        roll: 0, pitch: 0, yaw: 0,
        quatX: 0, quatY: 0, quatZ: 0, quatW: 1,
        rotX: 0, rotY: 0, rotZ: 0,
        accX: 0, accY: 0, accZ: 0,
        gravX: 0, gravY: 0, gravZ: 0,
        isConnected: false
    )

    private var isStarted = false

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        guard manager.isDeviceMotionAvailable else {
            print("Headphone device motion NOT available (connect AirPods?)")
            return
        }
        guard !isStarted else { return }
        isStarted = true

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if let error = error { print("Headphone motion error: \(error)") }
            guard let self, let motion else { return }

            let att = motion.attitude
            let q = att.quaternion
            let rr = motion.rotationRate
            let ua = motion.userAcceleration
            let g  = motion.gravity

            // Back-compat simple fields
            self.roll = att.roll
            self.pitch = att.pitch

            // Full snapshot
            self.snapshot = MotionSnapshot(
                timestamp: Date().timeIntervalSince1970,
                roll: att.roll, pitch: att.pitch, yaw: att.yaw,
                quatX: q.x, quatY: q.y, quatZ: q.z, quatW: q.w,
                rotX: rr.x, rotY: rr.y, rotZ: rr.z,
                accX: ua.x, accY: ua.y, accZ: ua.z,
                gravX: g.x, gravY: g.y, gravZ: g.z,
                isConnected: self.isConnected
            )
        }
    }

    func stop() {
        guard isStarted else { return }
        manager.stopDeviceMotionUpdates()
        isStarted = false
    }
}

extension HeadTracker: CMHeadphoneMotionManagerDelegate {
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        isConnected = true
        snapshot = MotionSnapshot(
            timestamp: snapshot.timestamp,
            roll: snapshot.roll, pitch: snapshot.pitch, yaw: snapshot.yaw,
            quatX: snapshot.quatX, quatY: snapshot.quatY, quatZ: snapshot.quatZ, quatW: snapshot.quatW,
            rotX: snapshot.rotX, rotY: snapshot.rotY, rotZ: snapshot.rotZ,
            accX: snapshot.accX, accY: snapshot.accY, accZ: snapshot.accZ,
            gravX: snapshot.gravX, gravY: snapshot.gravY, gravZ: snapshot.gravZ,
            isConnected: true
        )
        print("Headphones connected")
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        isConnected = false
        snapshot = MotionSnapshot(
            timestamp: snapshot.timestamp,
            roll: snapshot.roll, pitch: snapshot.pitch, yaw: snapshot.yaw,
            quatX: snapshot.quatX, quatY: snapshot.quatY, quatZ: snapshot.quatZ, quatW: snapshot.quatW,
            rotX: snapshot.rotX, rotY: snapshot.rotY, rotZ: snapshot.rotZ,
            accX: snapshot.accX, accY: snapshot.accY, accZ: snapshot.accZ,
            gravX: snapshot.gravX, gravY: snapshot.gravY, gravZ: snapshot.gravZ,
            isConnected: false
        )
        print("Headphones disconnected")
    }
}

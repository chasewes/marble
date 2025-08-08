import CoreMotion
import Combine

final class HeadTracker: NSObject, ObservableObject {
    private let manager = CMHeadphoneMotionManager()

    @Published var roll: Double = 0
    @Published var pitch: Double = 0
    @Published var isConnected: Bool = false

    private var isStarted = false

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        // Important: use isDeviceMotionAvailable (not a nonexistent available())
        guard manager.isDeviceMotionAvailable else {
            print("Headphone device motion NOT available")
            return
        }
        // If AirPods are already connected, you’ll immediately get data.
        // Start updates on main queue so we can publish to @Published safely.
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if let error = error {
                print("Headphone motion error: \(error)")
            }
            guard let self, let attitude = motion?.attitude else { return }
            // Using roll/pitch directly is fine for this use case.
            self.roll = attitude.roll
            self.pitch = attitude.pitch
        }
        isStarted = true
        // Ask the manager for current connection state (not directly exposed),
        // but the delegate will fire when a device connects/disconnects.
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
        // If you started before the user connected, data will now begin flowing.
        print("Headphones connected")
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        isConnected = false
        print("Headphones disconnected")
    }
}

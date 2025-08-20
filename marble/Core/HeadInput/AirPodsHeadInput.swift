import Combine
import QuartzCore


final class AirPodsHeadInput: HeadInputProviding {
private let tracker = HeadTracker()
private let subject = PassthroughSubject<HeadPose, Never>()
private var cancellables = Set<AnyCancellable>()


var posePublisher: AnyPublisher<HeadPose, Never> { subject.eraseToAnyPublisher() }


func start() {
// Bridge HeadTracker's @Published values to a single HeadPose stream
tracker.$roll.combineLatest(tracker.$pitch)
.sink { [weak self] roll, pitch in
guard let self else { return }
let t = CACurrentMediaTime()
let pose = HeadPose(roll: roll, pitch: pitch, yaw: 0, timestamp: t)
self.subject.send(pose)
}
.store(in: &cancellables)
tracker.start()
}


func stop() {
tracker.stop()
cancellables.removeAll()
}
}

import Combine


protocol HeadInputProviding {
var posePublisher: AnyPublisher<HeadPose, Never> { get }
func start()
func stop()
}

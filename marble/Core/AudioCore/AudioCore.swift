import CoreGraphics


final class AudioCore: AudioService {
private let engine = AudioEngine()


func start() { engine.start() }
func stop() { engine.stop() }


func setVelocity(_ v: Double) { engine.setVelocity(v) }
func playImpact(intensity: Float) { engine.playImpact(intensity: intensity) }
func updatePosition(point: CGPoint, sceneSize: CGSize) { engine.updatePosition(point: point, sceneSize: sceneSize) }
}

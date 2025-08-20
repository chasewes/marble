import CoreGraphics
import SpriteKit


// MARK: - Input Models
struct HeadPose {
let roll: Double // radians
let pitch: Double // radians
let yaw: Double // radians (not always provided by AirPods)
let timestamp: TimeInterval
}


struct MovementState {
let pose: HeadPose
let velocity01: Double // 0..1 normalized movement energy
let gravity: CGVector // world gravity to apply to physics
}


// MARK: - Services
protocol AudioService {
func setVelocity(_ v: Double)
func playImpact(intensity: Float)
func updatePosition(point: CGPoint, sceneSize: CGSize)
}


protocol GameServices {
var audio: AudioService { get }
}


// Simple service container used by the app
struct Services: GameServices {
let audio: AudioService
}


// MARK: - Game Plugin Protocol
protocol GamePlugin {
static var id: String { get }
static var displayName: String { get }


func makeScene(size: CGSize, services: GameServices) -> SKScene
func handle(input: MovementState)
}

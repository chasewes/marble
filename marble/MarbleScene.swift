import SpriteKit

final class MarbleScene: SKScene {
    private let ball = SKShapeNode(circleOfRadius: 24)
    var onSpeedChange: ((Double) -> Void)?

    override func didMove(to view: SKView) {
        physicsBody = SKPhysicsBody(edgeLoopFrom: frame)

        ball.fillColor = .white
        ball.strokeColor = .clear
        ball.position = CGPoint(x: frame.midX, y: frame.midY)
        ball.physicsBody = SKPhysicsBody(circleOfRadius: 24)
        ball.physicsBody?.restitution = 0.2
        ball.physicsBody?.friction = 0.4
        ball.physicsBody?.linearDamping = 0.3
        addChild(ball)
    }

    override func update(_ currentTime: TimeInterval) {
        let v = ball.physicsBody?.velocity ?? .zero
        let speed = min(hypot(v.dx, v.dy) / 1200.0, 1.0)
        onSpeedChange?(Double(speed))
    }

    func setGravity(_ g: CGVector) {
        physicsWorld.gravity = g
    }
}

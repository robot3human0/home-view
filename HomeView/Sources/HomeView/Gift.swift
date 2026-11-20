import AppKit
import QuartzCore

/// Qorbobo tashlab ketadigan sovg‘a qutisi. O‘yin rejimida qor bilan ursangiz ochiladi.
final class Gift {
    let root: CALayer
    private(set) var position: CGPoint
    private(set) var landed = false
    private(set) var isGone = false
    private var velocityY: CGFloat = 0
    private var spin: CGFloat = CGFloat.random(in: -0.3...0.3)
    private var age: CGFloat = 0

    init(at point: CGPoint, part: Part) {
        position = point
        root = partLayer(part, at: point)
        root.zPosition = 22
    }

    var hitRect: CGRect {
        CGRect(x: position.x - 11, y: position.y - 3, width: 22, height: 22)
    }

    func update(dt: CGFloat, groundY: CGFloat) {
        if !landed {
            velocityY -= 520 * dt
            position.y += velocityY * dt
            spin += dt * 1.5
            if position.y <= groundY {
                position.y = groundY
                landed = true
                spin = 0
            }
            root.position = position
            setRotation(root, spin)
        } else {
            position.y = groundY
            root.position = position
            age += dt
            if age > 45 { remove() }
        }
    }

    func remove() {
        guard !isGone else { return }
        isGone = true
        instant { root.removeFromSuperlayer() }
    }
}

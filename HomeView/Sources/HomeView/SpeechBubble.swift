import AppKit
import QuartzCore

/// Personaj boshi ustida chiqadigan qisqa gap.
final class SpeechBubble {
    let layer = containerLayer()
    private(set) var isAlive = true

    init(text: String, scale: CGFloat) {
        let font = NSFont(name: "HelveticaNeue-Medium", size: 11) ?? NSFont.systemFont(ofSize: 11, weight: .medium)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let width = ceil(textSize.width) + 18
        let height: CGFloat = 21
        let fill = cg(0xFFFFFF, 0.97)

        let background = CAShapeLayer()
        background.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                 cornerWidth: 10, cornerHeight: 10, transform: nil)
        background.fillColor = fill
        background.strokeColor = cg(0x94A3B8)
        background.lineWidth = 1
        background.contentsScale = scale

        let tailPath = CGMutablePath()
        tailPath.addLines(between: [CGPoint(x: -4, y: -height / 2 + 0.6),
                                    CGPoint(x: 4, y: -height / 2 + 0.6),
                                    CGPoint(x: 0, y: -height / 2 - 6)])
        tailPath.closeSubpath()
        let tail = CAShapeLayer()
        tail.path = tailPath
        tail.fillColor = fill
        tail.contentsScale = scale

        let label = CATextLayer()
        label.string = text
        label.font = font
        label.fontSize = 11
        label.foregroundColor = cg(0x1F2937)
        label.alignmentMode = .center
        label.contentsScale = scale
        label.bounds = CGRect(x: 0, y: 0, width: width, height: ceil(textSize.height))
        label.position = .zero

        instant {
            layer.addSublayer(background)
            layer.addSublayer(tail)
            layer.addSublayer(label)
            layer.zPosition = 90
        }
    }

    func show(for duration: TimeInterval) {
        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.3
        pop.toValue = 1
        pop.duration = 0.15
        layer.add(pop, forKey: "pop")
        after(duration) { [weak self] in self?.dismiss() }
    }

    func dismiss() {
        guard isAlive else { return }
        isAlive = false
        instant { layer.opacity = 0 }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.3
        layer.add(fade, forKey: "fade")
        let bubble = layer
        after(0.32) { bubble.removeFromSuperlayer() }
    }
}

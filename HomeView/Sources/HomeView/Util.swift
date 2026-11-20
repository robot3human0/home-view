import AppKit
import QuartzCore

// MARK: - Ranglar

func cg(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let whiteColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

// MARK: - Kichik yordamchilar

func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
    if low > high { return low }
    return min(max(value, low), high)
}

/// p ehtimollik bilan true qaytaradi (0...1).
func chance(_ p: CGFloat) -> Bool {
    CGFloat.random(in: 0...1) < p
}

/// Berilgan vaqtdan keyin asosiy oqimda bajaradi.
func after(_ seconds: Double, _ body: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body)
}

/// Qatlam xususiyatlarini animatsiyasiz (darhol) o‘zgartirish.
func instant(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

// MARK: - Qatlamlar

/// O‘lchamsiz konteyner qatlam: ichidagi qatlamlar uning position nuqtasiga nisbatan joylashadi.
func containerLayer() -> CALayer {
    let layer = CALayer()
    layer.bounds = .zero
    layer.anchorPoint = .zero
    return layer
}

/// Rasm qismidan qatlam yasaydi. Qism koordinatalaridagi (0,0) nuqta — aylanish markazi (pivot),
/// u ota qatlamdagi `pivot` nuqtasiga qo‘yiladi.
func partLayer(_ part: Part, at pivot: CGPoint) -> CALayer {
    let layer = CALayer()
    layer.contents = part.image
    layer.contentsScale = Art.scale
    layer.contentsGravity = .resize
    layer.bounds = CGRect(origin: .zero, size: part.box.size)
    layer.anchorPoint = CGPoint(x: -part.box.minX / part.box.width, y: -part.box.minY / part.box.height)
    layer.position = pivot
    return layer
}

func setRotation(_ layer: CALayer, _ angle: CGFloat) {
    layer.setValue(angle, forKeyPath: "transform.rotation.z")
}

/// Cheksiz aylanish (g‘ildiraklar uchun).
func spinForever(_ layer: CALayer, duration: CFTimeInterval, clockwise: Bool = true) {
    let spin = CABasicAnimation(keyPath: "transform.rotation.z")
    spin.fromValue = 0
    spin.toValue = clockwise ? -2 * CGFloat.pi : 2 * CGFloat.pi
    spin.duration = duration
    spin.repeatCount = .infinity
    layer.add(spin, forKey: "spin")
}

/// Cheksiz miltillash (chiroqlar uchun).
func blinkForever(_ layer: CALayer, low: Float, duration: CFTimeInterval) {
    let blink = CABasicAnimation(keyPath: "opacity")
    blink.fromValue = 1
    blink.toValue = low
    blink.duration = duration
    blink.autoreverses = true
    blink.repeatCount = .infinity
    layer.add(blink, forKey: "blink")
}

/// Oldinga-orqaga tebranish (oyoq-qo‘llar uchun).
func swingForever(_ layer: CALayer, amplitude: CGFloat, half: CFTimeInterval, key: String) {
    let swing = CABasicAnimation(keyPath: "transform.rotation.z")
    swing.fromValue = amplitude
    swing.toValue = -amplitude
    swing.duration = half
    swing.autoreverses = true
    swing.repeatCount = .infinity
    swing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(swing, forKey: key)
}

/// Yuqoriga sakrash (position.y ga qo‘shiladi, boshqa harakatni buzmaydi).
func bounce(_ layer: CALayer, height: CGFloat, duration: CFTimeInterval, repeats: Float, key: String) {
    let jump = CAKeyframeAnimation(keyPath: "position.y")
    jump.values = [0, height, 0]
    jump.keyTimes = [0, 0.5, 1]
    jump.duration = duration
    jump.repeatCount = repeats
    jump.isAdditive = true
    jump.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
    layer.add(jump, forKey: key)
}

/// "Paydo bo‘lish" effekti: kichikdan kattalashib, o‘z o‘lchamiga qaytadi.
func popIn(_ layer: CALayer) {
    let pop = CAKeyframeAnimation(keyPath: "transform.scale")
    pop.values = [0.2, 1.12, 1.0]
    pop.keyTimes = [0, 0.65, 1]
    pop.duration = 0.28
    layer.add(pop, forKey: "pop")
}

// MARK: - Geometriya

/// Nuqtalar orqali silliq yopiq egri chiziq (qor dog‘i shakli uchun).
func smoothClosedPath(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard points.count > 2 else { return path }
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    path.move(to: mid(points[points.count - 1], points[0]))
    for i in 0..<points.count {
        let next = points[(i + 1) % points.count]
        path.addQuadCurve(to: mid(points[i], next), control: points[i])
    }
    path.closeSubpath()
    return path
}

/// Takrorlanadigan tasodif (rasmlar har safar bir xil chiqishi uchun).
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1442695040888963407
    }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * next()
    }
}

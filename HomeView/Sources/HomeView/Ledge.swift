import AppKit
import QuartzCore

/// Qor yig‘iladigan "tokcha": oynaning yuqori qirrasi yoki ekran pasti (yer).
///
/// Qor balandligi 3 px enli ustunlarga bo‘lingan massivda saqlanadi (heightmap).
/// Har bir ustun — "shu joyda necha piksel qor bor". Tokcha siljisa, massiv
/// u bilan birga siljiydi (koordinatalar tokchaning chap chetiga nisbatan).
final class Ledge {
    let id: CGWindowID
    let isGround: Bool
    let colW: CGFloat = 3
    private(set) var originX: CGFloat
    private(set) var baseY: CGFloat
    private(set) var width: CGFloat
    var heights: [CGFloat]
    private(set) var visible: [Bool]
    let maxHeight: CGFloat
    let layer = CAShapeLayer()
    /// Qor qatlamining tagidagi yumshoq soya — qatlamga chuqurlik beradi (GPU chizadi, ilova emas).
    private let shade = CAGradientLayer()
    private let shadeMask = CAShapeLayer()
    private var shadeDepth: CGFloat { isGround ? 60 : 22 }
    var dirty = true
    var lastSeen: TimeInterval = 0
    private var pendingLeft: CGFloat = 0
    private var pendingRight: CGFloat = 0

    init(id: CGWindowID, originX: CGFloat, baseY: CGFloat, width: CGFloat, isGround: Bool, scale: CGFloat) {
        self.id = id
        self.isGround = isGround
        self.originX = originX
        self.baseY = baseY
        self.width = width
        let columns = max(1, Int(ceil(width / 3)))
        heights = Array(repeating: 0, count: columns)
        visible = Array(repeating: true, count: columns)
        maxHeight = isGround ? 150 : 28
        layer.fillColor = whiteColor
        layer.strokeColor = cg(0xA9B9CF, 0.95)
        layer.lineWidth = 1
        layer.lineJoin = .round
        layer.contentsScale = scale
        layer.bounds = .zero
        layer.anchorPoint = .zero
        layer.zPosition = isGround ? 12 : 10
        layer.position = CGPoint(x: originX, y: baseY)
        shadeMask.fillColor = whiteColor
        shade.mask = shadeMask
        shade.startPoint = CGPoint(x: 0.5, y: 0)
        shade.endPoint = CGPoint(x: 0.5, y: 1)
        shade.frame = CGRect(x: 0, y: 0, width: width, height: isGround ? 60 : 22)
        shade.colors = [cg(0x7F95B2, 0.34), cg(0x7F95B2, 0)]
        layer.addSublayer(shade)
    }

    /// To‘plangan narsaning rangi (qor, gul barglari, paxmoq, barglar).
    func setColors(fill: CGColor, stroke: CGColor) {
        let base = stroke.copy(alpha: 0.34) ?? stroke
        let clear = stroke.copy(alpha: 0) ?? stroke
        instant {
            layer.fillColor = fill
            layer.strokeColor = stroke
            shade.colors = [base, clear]
        }
    }

    // MARK: - O‘qish

    func column(at x: CGFloat) -> Int? {
        guard x.isFinite else { return nil }
        let i = Int(floor((x - originX) / colW))
        return (i >= 0 && i < heights.count) ? i : nil
    }

    func columnX(_ i: Int) -> CGFloat {
        originX + (CGFloat(i) + 0.5) * colW
    }

    /// Qor qoplamining ustki nuqtasi (sahna koordinatasida). Ustun ko‘rinmasa nil.
    func surfaceY(atX x: CGFloat) -> CGFloat? {
        guard let i = column(at: x), visible[i] else { return nil }
        return baseY + heights[i]
    }

    func height(atX x: CGFloat) -> CGFloat {
        guard let i = column(at: x) else { return 0 }
        return heights[i]
    }

    var average: CGFloat {
        heights.isEmpty ? 0 : heights.reduce(0, +) / CGFloat(heights.count)
    }

    var total: CGFloat { heights.reduce(0, +) }

    var peak: CGFloat { heights.max() ?? 0 }

    /// Tokchaning qancha qismida qor `depth` pikseldan qalin (0...1).
    func coverage(above depth: CGFloat) -> CGFloat {
        guard !heights.isEmpty else { return 0 }
        var count = 0
        for value in heights where value > depth {
            count += 1
        }
        return CGFloat(count) / CGFloat(heights.count)
    }

    // MARK: - Qo‘shish / olish

    /// Tushgan qor parchasini qo‘shni ustunlarga yoyib qo‘shadi.
    func deposit(atX x: CGFloat, amount: CGFloat) {
        guard let i = column(at: x) else { return }
        add(i, amount * 0.5)
        add(i - 1, amount * 0.25)
        add(i + 1, amount * 0.25)
        dirty = true
    }

    private func add(_ i: Int, _ amount: CGFloat) {
        guard i >= 0, i < heights.count else { return }
        heights[i] = min(maxHeight, heights[i] + amount)
    }

    /// x0...x1 oralig‘idan ko‘pi bilan `depth` piksel qor oladi. Olingan umumiy miqdorni qaytaradi.
    @discardableResult
    func remove(fromX x0: CGFloat, toX x1: CGFloat, depth: CGFloat,
                keep: CGFloat = 0, skip: ((CGFloat) -> Bool)? = nil) -> CGFloat {
        guard !heights.isEmpty, x0.isFinite, x1.isFinite else { return 0 }
        let a = max(0, Int(floor((min(x0, x1) - originX) / colW)))
        let b = min(heights.count - 1, Int(floor((max(x0, x1) - originX) / colW)))
        guard a <= b else { return 0 }
        var removed: CGFloat = 0
        for i in a...b {
            if let skip, skip(columnX(i)) { continue }
            let take = max(0, min(depth, heights[i] - keep))
            heights[i] -= take
            removed += take
        }
        if removed > 0 { dirty = true }
        return removed
    }

    // MARK: - Fizika

    /// "Tabiiy qiyalik": qo‘shni ustunlar farqi juda katta bo‘lsa, qor sirg‘alib tekislanadi.
    /// Oyna chetlaridan oshib ketgan qor (left/right) pastga to‘kiladi.
    func relax() -> (left: CGFloat, right: CGFloat) {
        let n = heights.count
        guard n > 1 else { return (0, 0) }
        let repose: CGFloat = 2.0
        var changed = false
        for _ in 0..<2 {
            for i in 0..<(n - 1) {
                let diff = heights[i] - heights[i + 1]
                let absDiff = abs(diff)
                if absDiff > repose {
                    let t = (absDiff - repose) * 0.3
                    if diff > 0 {
                        heights[i] -= t
                        heights[i + 1] += t
                    } else {
                        heights[i] += t
                        heights[i + 1] -= t
                    }
                    changed = true
                }
            }
        }
        var outLeft: CGFloat = 0
        var outRight: CGFloat = 0
        if !isGround {
            if heights[0] > 4 {
                let t = (heights[0] - 4) * 0.35
                heights[0] -= t
                pendingLeft += t
                changed = true
            }
            if heights[n - 1] > 4 {
                let t = (heights[n - 1] - 4) * 0.35
                heights[n - 1] -= t
                pendingRight += t
                changed = true
            }
            if pendingLeft >= 1.5 { outLeft = pendingLeft; pendingLeft = 0 }
            if pendingRight >= 1.5 { outRight = pendingRight; pendingRight = 0 }
        }
        if changed { dirty = true }
        return (outLeft, outRight)
    }

    func melt(_ amount: CGFloat) {
        var any = false
        for i in heights.indices where heights[i] > 0 {
            heights[i] = max(0, heights[i] - amount)
            any = true
        }
        if any { dirty = true }
    }

    func clear() {
        for i in heights.indices { heights[i] = 0 }
        pendingLeft = 0
        pendingRight = 0
        dirty = true
    }

    // MARK: - Joylashuv

    func move(originX: CGFloat, baseY: CGFloat) {
        self.originX = originX
        self.baseY = baseY
        let point = CGPoint(x: originX, y: baseY)
        instant { layer.position = point }
    }

    /// Oyna eni o‘zgarganda chaqiriladi: qor yangidan boshlanadi.
    func resize(originX: CGFloat, baseY: CGFloat, width: CGFloat) {
        move(originX: originX, baseY: baseY)
        self.width = width
        let columns = max(1, Int(ceil(width / colW)))
        heights = Array(repeating: 0, count: columns)
        visible = Array(repeating: true, count: columns)
        dirty = true
        let depth = shadeDepth
        instant { shade.frame = CGRect(x: 0, y: 0, width: width, height: depth) }
    }

    /// Oldidagi boshqa oynalar bilan yopilgan joylar — u yerga qor tushmaydi va chizilmaydi.
    func setCovered(_ intervals: [(CGFloat, CGFloat)]) {
        var changed = false
        for i in heights.indices {
            let x = columnX(i)
            var isVisible = true
            for (a, b) in intervals where x >= a && x <= b {
                isVisible = false
                break
            }
            if visible[i] != isVisible {
                visible[i] = isVisible
                changed = true
            }
        }
        if changed { dirty = true }
    }

    // MARK: - Chizish

    func redrawIfNeeded(sceneWidth: CGFloat) {
        guard dirty else { return }
        dirty = false
        let path = CGMutablePath()
        let n = heights.count
        var i = 0
        while i < n {
            if !drawable(i, sceneWidth) {
                i += 1
                continue
            }
            var j = i
            while j < n && drawable(j, sceneWidth) { j += 1 }
            appendSegment(path, from: i, to: j)
            i = j
        }
        instant {
            layer.path = path
            shadeMask.path = path
        }
    }

    private func drawable(_ i: Int, _ sceneWidth: CGFloat) -> Bool {
        guard visible[i], heights[i] > 0.25 else { return false }
        let globalX = originX + CGFloat(i) * colW
        return globalX > -colW * 2 && globalX < sceneWidth + colW
    }

    /// Har 3-ustun (9 pt) bitta nuqta bo‘ladi va egri chiziq o‘rniga to‘g‘ri chiziq ishlatiladi:
    /// qor tabiiy qiyalikda tekislangani uchun ko‘zga farq sezilmaydi, chizish esa ~6 barobar yengil.
    static let drawStride = 3

    private func appendSegment(_ path: CGMutablePath, from a: Int, to b: Int) {
        let x0 = CGFloat(a) * colW
        let x1 = CGFloat(b) * colW
        let last = b - 1
        path.move(to: CGPoint(x: x0, y: 0))
        path.addLine(to: CGPoint(x: x0, y: heights[a] * 0.5))
        var k = a
        while k < last {
            path.addLine(to: CGPoint(x: (CGFloat(k) + 0.5) * colW, y: heights[k]))
            k += Ledge.drawStride
        }
        path.addLine(to: CGPoint(x: (CGFloat(last) + 0.5) * colW, y: heights[last]))
        path.addLine(to: CGPoint(x: x1, y: heights[last] * 0.5))
        path.addLine(to: CGPoint(x: x1, y: 0))
        path.closeSubpath()
    }
}

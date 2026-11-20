import CoreGraphics
import Foundation

/// Boshqa ilovalar oynasining faqat ramkasi (o‘rni va o‘lchami).
/// Oyna ichidagi narsalar o‘qilmaydi — shuning uchun "Screen Recording" ruxsati kerak emas.
struct TrackedWindow {
    let id: CGWindowID
    /// AppKit global koordinatalari (asosiy ekranning pastki chap burchagidan).
    let frame: CGRect
    /// 0 — eng oldingi oyna.
    let order: Int
}

/// Ekrandagi oddiy oynalar ro‘yxatini oladi. Fon oqimida chaqiriladi —
/// shuning uchun ko‘p oyna ochiq bo‘lsa ham animatsiya qotmaydi.
final class WindowTracker {
    private let myPID = ProcessInfo.processInfo.processIdentifier

    /// - Parameter primaryHeight: asosiy monitor balandligi (koordinatalarni aylantirish uchun).
    func snapshot(primaryHeight: CGFloat) -> [TrackedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }

        var result: [TrackedWindow] = []
        result.reserveCapacity(raw.count)
        for info in raw {
            // Faqat oddiy ilova oynalari (layer 0). Menyu, Dock, bildirishnomalar boshqa qatlamda.
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { continue }
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != myPID else { continue }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha < 0.1 { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "Window Server" || owner == "Dock" { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            guard bounds.width >= 90, bounds.height >= 50 else { continue }
            let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            // CoreGraphics'da y pastga, AppKit'da yuqoriga qarab o‘sadi.
            let frame = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY,
                               width: bounds.width, height: bounds.height)
            result.append(TrackedWindow(id: id, frame: frame, order: result.count))
        }
        return result
    }
}

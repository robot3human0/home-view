import AppKit
import QuartzCore

/// Ekranga yopishtirilgan "shisha": ramkasiz, shaffof, barcha oynalar ustida turadigan panel.
/// Odatda sichqoncha bosishlarini o‘tkazib yuboradi (ignoresMouseEvents = true).
final class OverlayPanel: NSPanel {
    convenience init(screen: NSScreen) {
        self.init(contentRect: screen.frame,
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Oddiy oynalar va Dock ustida, lekin menyu satri ostida —
        // shunda o‘yin rejimida ham menyu satridagi ❄ belgisini bosish mumkin.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// macOS oynani menyu satri ostiga surib qo‘ymasligi uchun.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Core Animation qatlamlarini o‘zida saqlaydigan ko‘rinish. O‘yin rejimida bosishlarni dunyoga uzatadi.
final class OverlayView: NSView {
    weak var world: SnowWorld?

    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        world?.handleClick(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        world?.handleDrag(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        world?.handleMouseUp(at: point)
    }

    /// ⌥ + g‘ildirak (yoki trackpadda ikki barmoq) — sichqoncha ostidagi narsaning o‘lchamini surib o‘zgartirish.
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.option) else { return }
        var delta = event.scrollingDeltaY
        if delta == 0 { delta = event.scrollingDeltaX }
        if !event.hasPreciseScrollingDeltas { delta *= 8 }
        let point = convert(event.locationInWindow, from: nil)
        world?.handleResizeScroll(at: point, delta: delta)
    }
}

/// Bitta monitor uchun: panel + ko‘rinish + qishki dunyo.
final class OverlayController {
    let screen: NSScreen
    let panel: OverlayPanel
    let view: OverlayView
    let world: SnowWorld

    init(screen: NSScreen, isPrimary: Bool) {
        self.screen = screen
        panel = OverlayPanel(screen: screen)
        view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))

        // Layer-hosting: ko‘rinishning qatlamini o‘zimiz beramiz, AppKit uni chizmaydi.
        let rootLayer = CALayer()
        rootLayer.frame = view.bounds
        rootLayer.masksToBounds = false
        rootLayer.contentsScale = screen.backingScaleFactor
        view.layer = rootLayer
        view.wantsLayer = true

        world = SnowWorld(screen: screen, root: rootLayer, theme: SeasonTheme.current, isPrimary: isPrimary)
        view.world = world
        world.hostView = view
        panel.contentView = view
        applySettings()
        panel.orderFrontRegardless()
    }

    func applySettings() {
        let settings = Settings.shared
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if settings.showInFullScreen { behavior.insert(.fullScreenAuxiliary) }
        panel.collectionBehavior = behavior
        panel.sharingType = settings.hideFromCapture ? .none : .readOnly
        world.applySettings()
    }

    func setPlayMode(_ on: Bool) {
        panel.ignoresMouseEvents = !on
        world.setPlayMode(on)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

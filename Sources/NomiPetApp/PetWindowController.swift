import AppKit

enum PetDragPhase {
    case started
    case movingLeft
    case movingRight
    case ended
}

@MainActor
final class PetWindowController: NSObject {
    private static let baseSize = NSSize(width: 420, height: 300)

    private let window: NSWindow
    private let settings: SettingsStore
    private let petView: PetView
    private var dragStart: NSPoint?
    private var lastMouseX: CGFloat?
    private var mousePolicyTimer: Timer?
    private var rightClickMonitor: Any?
    private var isMouseOverPet = false
    private var currentBubbleStyle: BubblePresentationStyle = .compact

    var onDragPhase: ((PetDragPhase) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenChat: (() -> Void)?
    var onHeadpat: (() -> Void)?
    var onRightClick: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        let initialSize = Self.size(for: settings)
        petView = PetView(frame: NSRect(origin: .zero, size: initialSize))
        petView.petScale = settings.petScale
        petView.bubbleScale = settings.bubbleScale
        petView.bubbleOffset = NSPoint(x: settings.bubbleOffsetX, y: settings.bubbleOffsetY)
        petView.bubbleTitleFontSize = settings.bubbleTitleFontSize
        petView.bubbleBodyFontSize = settings.bubbleBodyFontSize
        petView.bubbleLineSpacing = settings.bubbleLineSpacing
        petView.bubbleTextPadding = settings.bubbleTextPadding
        window = NSWindow(
            contentRect: NSRect(x: 980, y: 160, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configureWindow()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    func update(
        image: NSImage?,
        line: String?,
        status: AssistantStatus?,
        style: BubblePresentationStyle = .compact
    ) {
        petView.image = image
        if currentBubbleStyle != style {
            currentBubbleStyle = style
            petView.bubbleStyle = style
            resizeWindowForCurrentSettings()
        } else {
            petView.bubbleStyle = style
        }
        if line?.isEmpty == false {
            applyAdaptiveBubblePlacement()
        }
        petView.bubbleText = line
        petView.bubbleStatus = status
    }

    private func configureWindow() {
        let container = DraggableContainerView(
            frame: petView.frame,
            isInteractivePoint: { [weak petView] point in
                petView?.isPetPoint(point) == true
            },
            trackingRect: { [weak petView] in
                petView?.petInteractionRect() ?? .zero
            },
            onMouseEvent: { [weak self] event in
                self?.handleDrag(event)
            },
            onHoverChanged: { [weak self] isHovering in
                self?.onHoverChanged?(isHovering)
            },
            onRightClick: { [weak self] in
                self?.onRightClick?()
            }
        )
        container.autoresizingMask = [.width, .height]
        petView.autoresizingMask = [.width, .height]
        window.contentView = container
        window.contentView?.addSubview(petView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isMovableByWindowBackground = false
        window.isRestorable = false

        // Local event monitor: captures right-click events dispatched to our app.
        // acceptsFirstMouse only covers left-click; right-click needs an explicit
        // monitor to work reliably when our app is not the frontmost app.
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            let pt = self.petViewPoint(forScreenPoint: NSEvent.mouseLocation)
            if self.petView.isPetPoint(pt) {
                self.onRightClick?()
                return nil  // consume — prevents macOS routing to desktop/other app
            }
            return event
        }

        startMousePolicyTimer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applySettings),
            name: SettingsStore.sizeDidChange,
            object: settings
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyBubbleSettings),
            name: SettingsStore.bubbleDidChange,
            object: settings
        )
    }

    private func handleDrag(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if event.clickCount >= 3 {
                onOpenSettings?()
                return
            } else if event.clickCount == 2 {
                onHeadpat?()
                return
            }
            dragStart = event.locationInWindow
            lastMouseX = NSEvent.mouseLocation.x
            onDragPhase?(.started)
        case .leftMouseDragged:
            guard let dragStart else { return }
            let mouse = NSEvent.mouseLocation
            let newOrigin = NSPoint(x: mouse.x - dragStart.x, y: mouse.y - dragStart.y)
            window.setFrameOrigin(newOrigin)
            if let lastMouseX {
                let deltaX = mouse.x - lastMouseX
                if deltaX > 1 {
                    onDragPhase?(.movingRight)
                } else if deltaX < -1 {
                    onDragPhase?(.movingLeft)
                }
            }
            lastMouseX = mouse.x
        case .leftMouseUp:
            dragStart = nil
            lastMouseX = nil
            applyAdaptiveBubblePlacement()
            onDragPhase?(.ended)
        default:
            break
        }
    }

    var frame: NSRect { window.frame }

    func moveBy(dx: CGFloat) {
        guard let screen = window.screen else { return }
        var origin = window.frame.origin
        origin.x = max(screen.visibleFrame.minX,
                       min(screen.visibleFrame.maxX - window.frame.width, origin.x + dx))
        window.setFrameOrigin(origin)
    }

    @objc private func applySettings() {
        petView.petScale = settings.petScale
        resizeWindowForCurrentSettings()
    }

    @objc private func applyBubbleSettings() {
        petView.bubbleScale = settings.bubbleScale
        petView.bubbleOffset = NSPoint(x: settings.bubbleOffsetX, y: settings.bubbleOffsetY)
        petView.bubbleTitleFontSize = settings.bubbleTitleFontSize
        petView.bubbleBodyFontSize = settings.bubbleBodyFontSize
        petView.bubbleLineSpacing = settings.bubbleLineSpacing
        petView.bubbleTextPadding = settings.bubbleTextPadding
        resizeWindowForCurrentSettings()
    }

    private func resizeWindowForCurrentSettings() {
        let oldFrame = window.frame
        let newSize = Self.size(for: settings, style: currentBubbleStyle)
        let newOrigin = NSPoint(
            x: oldFrame.maxX - newSize.width,
            y: oldFrame.minY
        )
        let newFrame = NSRect(origin: newOrigin, size: newSize)
        window.setFrame(newFrame, display: true)
        petView.frame = NSRect(origin: .zero, size: newSize)
        window.contentView?.frame = NSRect(origin: .zero, size: newSize)
        applyAdaptiveBubblePlacement()
        updateMouseEventPolicy()
    }

    private func applyAdaptiveBubblePlacement() {
        guard dragStart == nil else { return }
        let petCenter = petScreenCenter()
        guard let screenFrame = screenFrame(containing: petCenter) else { return }
        let layout = BubblePlacement.resolve(
            petScreenCenter: petCenter,
            screenFrame: screenFrame,
            windowSize: window.frame.size,
            petRectLeftBubble: petView.petInteractionRect(for: .left),
            petRectRightBubble: petView.petInteractionRect(for: .right),
            bubbleRectLeft: petView.bubbleRect(for: .left),
            bubbleRectRight: petView.bubbleRect(for: .right),
            currentSide: petView.bubbleSide
        )

        guard layout.side != petView.bubbleSide else { return }
        petView.bubbleSide = layout.side
        window.setFrame(layout.windowFrame, display: true)
        petView.frame = NSRect(origin: .zero, size: layout.windowFrame.size)
        window.contentView?.frame = NSRect(origin: .zero, size: layout.windowFrame.size)
        updateMouseEventPolicy()
    }

    private func petScreenCenter() -> NSPoint {
        let petRect = petView.petInteractionRect()
        let frame = window.frame
        return NSPoint(
            x: frame.minX + petRect.midX,
            y: frame.maxY - petRect.midY
        )
    }

    private func screenFrame(containing point: NSPoint) -> NSRect? {
        let nearbyScreen = NSScreen.screens.first {
            $0.visibleFrame.insetBy(dx: -160, dy: -160).contains(point)
        }
        return (nearbyScreen ?? window.screen ?? NSScreen.main)?.visibleFrame
    }

    private static func size(for settings: SettingsStore, style: BubblePresentationStyle = .compact) -> NSSize {
        let scale = settings.petScale
        let growth = max(0, scale - 0.55)
        let petSize = NSSize(
            width: baseSize.width + 190 * growth,
            height: baseSize.height + 210 * growth
        )
        let bubbleSize = NSSize(width: 366 * settings.bubbleScale, height: 96 * settings.bubbleScale)
        let bubbleWidth = 24 + settings.bubbleOffsetX + bubbleSize.width + 24
        let bubbleHeight = 18 + settings.bubbleOffsetY + bubbleSize.height + 24
        return NSSize(
            width: max(petSize.width, bubbleWidth),
            height: max(petSize.height, bubbleHeight)
        )
    }

    private func startMousePolicyTimer() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMouseEventPolicy()
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        mousePolicyTimer = timer
        updateMouseEventPolicy()
    }

    private func updateMouseEventPolicy() {
        guard window.isVisible else { return }
        if dragStart != nil {
            window.ignoresMouseEvents = false
            return
        }

        let contentPoint = petViewPoint(forScreenPoint: NSEvent.mouseLocation)
        let isInsidePet = petView.isPetPoint(contentPoint)

        if isInsidePet != isMouseOverPet {
            isMouseOverPet = isInsidePet
            onHoverChanged?(isInsidePet)
        }
        window.ignoresMouseEvents = isInsidePet == false
    }

    private func petViewPoint(forScreenPoint screenPoint: NSPoint) -> NSPoint {
        let frame = window.frame
        return NSPoint(
            x: screenPoint.x - frame.minX,
            y: frame.maxY - screenPoint.y
        )
    }
}

@MainActor
private final class DraggableContainerView: NSView {
    private let isInteractivePoint: (NSPoint) -> Bool
    private let trackingRect: () -> NSRect
    private let onMouseEvent: (NSEvent) -> Void
    private let onHoverChanged: (Bool) -> Void
    private let onRightClick: () -> Void
    private var hoverTrackingArea: NSTrackingArea?

    init(
        frame frameRect: NSRect,
        isInteractivePoint: @escaping (NSPoint) -> Bool,
        trackingRect: @escaping () -> NSRect,
        onMouseEvent: @escaping (NSEvent) -> Void,
        onHoverChanged: @escaping (Bool) -> Void,
        onRightClick: @escaping () -> Void
    ) {
        self.isInteractivePoint = isInteractivePoint
        self.trackingRect = trackingRect
        self.onMouseEvent = onMouseEvent
        self.onHoverChanged = onHoverChanged
        self.onRightClick = onRightClick
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isInteractivePoint(point) {
            return self
        }
        let flippedPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        return isInteractivePoint(flippedPoint) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onMouseEvent(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseEvent(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseEvent(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        // hitTest already ensured we're over the pet; call directly.
        onRightClick()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let rect = trackingRect()
        guard rect.isEmpty == false else {
            super.updateTrackingAreas()
            return
        }

        let area = NSTrackingArea(
            rect: rect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        if isInteractivePoint(convert(event.locationInWindow, from: nil)) {
            onHoverChanged(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged(false)
    }
}

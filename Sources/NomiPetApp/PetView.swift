import AppKit

final class PetView: NSView {
    private let basePetSize = NSSize(width: 246, height: 280)
    private let baseBubbleRect = NSRect(x: 24, y: 18, width: 366, height: 96)
    private var bubbleScrollStartedAt = Date.timeIntervalSinceReferenceDate
    private var scrollingRedrawPending = false

    var bubbleScale: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }

    var bubbleOffset = NSPoint(x: 0, y: 0) {
        didSet { needsDisplay = true }
    }

    var bubbleTitleFontSize: CGFloat = SettingsStore.defaultBubbleTitleFontSize {
        didSet { needsDisplay = true }
    }

    var bubbleBodyFontSize: CGFloat = SettingsStore.defaultBubbleBodyFontSize {
        didSet { needsDisplay = true }
    }

    var bubbleLineSpacing: CGFloat = SettingsStore.defaultBubbleLineSpacing {
        didSet { needsDisplay = true }
    }

    var bubbleTextPadding: CGFloat = SettingsStore.defaultBubbleTextPadding {
        didSet { needsDisplay = true }
    }

    var image: NSImage? {
        didSet {
            rebuildHitMask()
            needsDisplay = true
        }
    }

    var bubbleText: String? {
        didSet {
            if bubbleText != oldValue {
                bubbleScrollStartedAt = Date.timeIntervalSinceReferenceDate
            }
            needsDisplay = true
        }
    }

    var bubbleStatus: AssistantStatus? {
        didSet { needsDisplay = true }
    }

    var bubbleStyle: BubblePresentationStyle = .compact {
        didSet {
            if bubbleStyle != oldValue {
                bubbleScrollStartedAt = Date.timeIntervalSinceReferenceDate
            }
            needsDisplay = true
        }
    }

    var petScale: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }

    var bubbleSide: BubbleSide = .left {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    private var hitMask: (width: Int, height: Int, alpha: [UInt8])?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        if let bubbleText, bubbleText.isEmpty == false {
            drawBubble(text: bubbleText)
        }

        guard let image else { return }
        let petBounds = petBounds(for: bubbleSide)
        let petRect = aspectFit(imageSize: image.size, in: petBounds)
        image.draw(
            in: petRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
    }

    private func drawBubble(text: String) {
        let lines = text.components(separatedBy: "\n")
        let title = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = lines.dropFirst().joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bubbleRect = bubbleBounds(for: bubbleSide)

        let path = NSBezierPath(roundedRect: bubbleRect, xRadius: 24, yRadius: 24)
        NSColor(calibratedWhite: 0.02, alpha: 0.88).setFill()
        path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let titleSize = max(SettingsStore.minBubbleTitleFontSize, min(SettingsStore.maxBubbleTitleFontSize, bubbleTitleFontSize))
        let bodySize = max(SettingsStore.minBubbleBodyFontSize, min(SettingsStore.maxBubbleBodyFontSize, bubbleBodyFontSize))
        let lineSpacing = max(SettingsStore.minBubbleLineSpacing, min(SettingsStore.maxBubbleLineSpacing, bubbleLineSpacing))
        let textPadding = max(SettingsStore.minBubbleTextPadding, min(SettingsStore.maxBubbleTextPadding, bubbleTextPadding))
        let verticalPadding = max(12, min(30, textPadding * 0.75))
        let statusIndicatorSize: CGFloat = 18
        let statusIndicatorRect = NSRect(
            x: bubbleRect.maxX - textPadding - statusIndicatorSize - 10,
            y: bubbleRect.minY + max(12, textPadding * 0.5),
            width: statusIndicatorSize,
            height: statusIndicatorSize
        )
        let statusReservedRight = max(70, textPadding + statusIndicatorSize + 34)
        drawStatusIndicator(in: statusIndicatorRect)

        if body.isEmpty {
            let singleParagraph = NSMutableParagraphStyle()
            singleParagraph.lineBreakMode = bubbleStyle == .dynamic ? .byWordWrapping : .byTruncatingTail
            singleParagraph.alignment = .left
            singleParagraph.lineSpacing = lineSpacing

            let singleRect = NSRect(
                x: bubbleRect.minX + textPadding,
                y: bubbleRect.minY + verticalPadding + 4,
                width: max(40, bubbleRect.width - textPadding - statusReservedRight),
                height: max(24, bubbleRect.height - verticalPadding * 2)
            )
            let singleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: bodySize, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: singleParagraph
            ]
            if bubbleStyle == .dynamic {
                drawScrollingBody(title, in: singleRect, attributes: singleAttrs)
            } else {
                (title as NSString).draw(in: singleRect, withAttributes: singleAttrs)
            }
            return
        }

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingTail
        titleParagraph.alignment = .left

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineBreakMode = bubbleStyle == .dynamic ? .byWordWrapping : .byTruncatingTail
        bodyParagraph.alignment = .left
        bodyParagraph.lineSpacing = lineSpacing

        let titleRect = NSRect(
            x: bubbleRect.minX + textPadding,
            y: bubbleRect.minY + verticalPadding,
            width: max(40, bubbleRect.width - textPadding - statusReservedRight),
            height: titleSize + max(7, lineSpacing + 6)
        )
        let bodyRect = NSRect(
            x: bubbleRect.minX + textPadding,
            y: titleRect.maxY + max(2, lineSpacing + 1),
            width: max(40, bubbleRect.width - textPadding - max(28, textPadding)),
            height: max(24, bubbleRect.maxY - titleRect.maxY - max(verticalPadding, lineSpacing + 9))
        )

        (title as NSString).draw(
            in: titleRect,
            withAttributes: [
                .font: NSFont.systemFont(ofSize: titleSize, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: titleParagraph
            ]
        )

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: bodySize, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.96),
            .paragraphStyle: bodyParagraph
        ]
        if bubbleStyle == .dynamic {
            drawScrollingBody(body, in: bodyRect, attributes: bodyAttributes)
        } else {
            (body as NSString).draw(in: bodyRect, withAttributes: bodyAttributes)
        }
    }

    private func drawScrollingBody(
        _ text: String,
        in rect: NSRect,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let contentHeight = measuredHeight(text: text, width: rect.width, attributes: attributes)
        guard contentHeight > rect.height + 1 else {
            (text as NSString).draw(in: rect, withAttributes: attributes)
            return
        }

        scheduleScrollingBubbleRedraw()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).setClip()
        let elapsed = Date.timeIntervalSinceReferenceDate - bubbleScrollStartedAt
        let offset = BubbleTextScroller.verticalOffset(
            contentHeight: contentHeight,
            viewportHeight: rect.height,
            elapsed: elapsed
        )
        (text as NSString).draw(
            in: NSRect(
                x: rect.minX,
                y: rect.minY - offset,
                width: rect.width,
                height: contentHeight + 6
            ),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func measuredHeight(
        text: String,
        width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        guard text.isEmpty == false else { return 0 }
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return ceil(rect.height) + 3
    }

    private func scheduleScrollingBubbleRedraw() {
        guard scrollingRedrawPending == false else { return }
        scrollingRedrawPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30.0) { [weak self] in
            self?.scrollingRedrawPending = false
            self?.needsDisplay = true
        }
    }

    private func drawStatusIndicator(in rect: NSRect) {
        guard let bubbleStatus else { return }

        let color: NSColor
        switch bubbleStatus {
        case .thinking, .running:
            color = NSColor(calibratedWhite: 0.82, alpha: 1)
        case .waiting:
            color = NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.28, alpha: 1)
        case .failed:
            color = NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.36, alpha: 1)
        case .completed:
            color = NSColor(calibratedRed: 0.36, green: 0.86, blue: 0.48, alpha: 1)
        case .stalled:
            color = NSColor(calibratedWhite: 0.62, alpha: 1)
        }

        if bubbleStatus == .thinking || bubbleStatus == .running {
            let start = CGFloat((Date().timeIntervalSinceReferenceDate * 180).truncatingRemainder(dividingBy: 360))
            let path = NSBezierPath()
            path.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: rect.width / 2 - 2,
                startAngle: start,
                endAngle: start + 280,
                clockwise: false
            )
            color.setStroke()
            path.lineWidth = 3
            path.lineCapStyle = .round
            path.stroke()
        } else {
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
        }
    }

    private func petBounds(for side: BubbleSide) -> NSRect {
        let safeScale = max(0.2, min(1.6, petScale))
        let size = NSSize(
            width: basePetSize.width * safeScale,
            height: basePetSize.height * safeScale
        )
        let sidePadding = 40 + max(0, safeScale - 1.0) * 24
        let bottomPadding: CGFloat = 20
        let x: CGFloat
        switch side {
        case .left:
            x = bounds.width - size.width - sidePadding
        case .right:
            x = sidePadding
        }
        return NSRect(
            x: x,
            y: bounds.height - size.height - bottomPadding,
            width: size.width,
            height: size.height
        )
    }

    func petInteractionRect() -> NSRect {
        petInteractionRect(for: bubbleSide)
    }

    func petInteractionRect(for side: BubbleSide) -> NSRect {
        if let image {
            return aspectFit(imageSize: image.size, in: petBounds(for: side))
        }
        return petBounds(for: side)
    }

    func bubbleRect(for side: BubbleSide) -> NSRect {
        bubbleBounds(for: side)
    }

    func isPetPoint(_ point: NSPoint) -> Bool {
        let rect = petInteractionRect()
        guard rect.contains(point) else { return false }
        guard let hitMask else { return true }

        let relativeX = (point.x - rect.minX) / rect.width
        let relativeY = (point.y - rect.minY) / rect.height
        let pixelX = Int((relativeX * CGFloat(hitMask.width)).rounded(.down))
        let pixelY = Int((relativeY * CGFloat(hitMask.height)).rounded(.down))
        return hasVisibleAlphaNear(x: pixelX, y: pixelY, in: hitMask)
    }

    private func aspectFit(imageSize: NSSize, in rect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return rect
        }

        let imageRatio = imageSize.width / imageSize.height
        let rectRatio = rect.width / rect.height
        let size: NSSize

        if rectRatio > imageRatio {
            size = NSSize(width: rect.height * imageRatio, height: rect.height)
        } else {
            size = NSSize(width: rect.width, height: rect.width / imageRatio)
        }

        return NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func bubbleBounds(for side: BubbleSide) -> NSRect {
        let safeScale = max(SettingsStore.minBubbleScale, min(SettingsStore.maxBubbleScale, bubbleScale))
        let size = bubbleSize(for: bubbleText ?? "", scale: safeScale)
        return NSRect(
            x: baseBubbleRect.minX + bubbleOffset.x,
            y: baseBubbleRect.minY + bubbleOffset.y,
            width: size.width,
            height: size.height
        )
    }

    private func bubbleSize(for text: String, scale: CGFloat) -> NSSize {
        return NSSize(
            width: baseBubbleRect.width * scale,
            height: baseBubbleRect.height * scale
        )
    }

    private func rebuildHitMask() {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            hitMask = nil
            return
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            hitMask = nil
            return
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var alpha = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            for col in 0..<width {
                alpha[row * width + col] = pixels[row * bytesPerRow + col * bytesPerPixel + 3]
            }
        }
        hitMask = (width, height, alpha)
    }

    private func hasVisibleAlphaNear(x: Int, y: Int, in mask: (width: Int, height: Int, alpha: [UInt8])) -> Bool {
        guard mask.width > 0, mask.height > 0 else { return false }
        let clampedX = min(max(0, x), mask.width - 1)
        let clampedY = min(max(0, y), mask.height - 1)
        let invertedY = mask.height - 1 - clampedY
        let radius = 2

        for sampleY in (clampedY - radius)...(clampedY + radius) {
            for sampleX in (clampedX - radius)...(clampedX + radius) {
                if alphaAt(x: sampleX, y: sampleY, in: mask) > 18 {
                    return true
                }
            }
        }

        for sampleY in (invertedY - radius)...(invertedY + radius) {
            for sampleX in (clampedX - radius)...(clampedX + radius) {
                if alphaAt(x: sampleX, y: sampleY, in: mask) > 18 {
                    return true
                }
            }
        }

        return false
    }

    private func alphaAt(x: Int, y: Int, in mask: (width: Int, height: Int, alpha: [UInt8])) -> UInt8 {
        guard x >= 0, y >= 0, x < mask.width, y < mask.height else { return 0 }
        return mask.alpha[y * mask.width + x]
    }
}

import AppKit

enum BubbleSide: Equatable, Sendable {
    case left
    case right

    var opposite: BubbleSide {
        self == .left ? .right : .left
    }
}

struct BubblePlacementLayout: Equatable, Sendable {
    let side: BubbleSide
    let windowFrame: NSRect
    let bubbleScreenRect: NSRect
}

enum BubblePlacement {
    private static let screenMargin: CGFloat = 8

    static func resolve(
        petScreenCenter: NSPoint,
        screenFrame: NSRect,
        windowSize: NSSize,
        petRectLeftBubble: NSRect,
        petRectRightBubble: NSRect,
        bubbleRectLeft: NSRect,
        bubbleRectRight: NSRect,
        currentSide: BubbleSide
    ) -> BubblePlacementLayout {
        let left = candidate(
            side: .left,
            petScreenCenter: petScreenCenter,
            windowSize: windowSize,
            petRect: petRectLeftBubble,
            bubbleRect: bubbleRectLeft
        )
        let right = candidate(
            side: .right,
            petScreenCenter: petScreenCenter,
            windowSize: windowSize,
            petRect: petRectRightBubble,
            bubbleRect: bubbleRectRight
        )
        let candidates: [BubbleSide: BubblePlacementLayout] = [.left: left, .right: right]
        let preferredSide: BubbleSide = petScreenCenter.x < screenFrame.midX ? .right : .left

        if let preferred = candidates[preferredSide], fits(preferred.bubbleScreenRect, in: screenFrame) {
            return preferred
        }

        if let current = candidates[currentSide], fits(current.bubbleScreenRect, in: screenFrame) {
            return current
        }

        if let opposite = candidates[currentSide.opposite], fits(opposite.bubbleScreenRect, in: screenFrame) {
            return opposite
        }

        return visibleWidth(left.bubbleScreenRect, in: screenFrame) >= visibleWidth(right.bubbleScreenRect, in: screenFrame) ? left : right
    }

    private static func candidate(
        side: BubbleSide,
        petScreenCenter: NSPoint,
        windowSize: NSSize,
        petRect: NSRect,
        bubbleRect: NSRect
    ) -> BubblePlacementLayout {
        let windowFrame = NSRect(
            x: petScreenCenter.x - petRect.midX,
            y: petScreenCenter.y + petRect.midY - windowSize.height,
            width: windowSize.width,
            height: windowSize.height
        )
        let bubbleScreenRect = NSRect(
            x: windowFrame.minX + bubbleRect.minX,
            y: windowFrame.maxY - bubbleRect.maxY,
            width: bubbleRect.width,
            height: bubbleRect.height
        )
        return BubblePlacementLayout(side: side, windowFrame: windowFrame, bubbleScreenRect: bubbleScreenRect)
    }

    private static func fits(_ rect: NSRect, in screenFrame: NSRect) -> Bool {
        rect.minX >= screenFrame.minX + screenMargin && rect.maxX <= screenFrame.maxX - screenMargin
    }

    private static func visibleWidth(_ rect: NSRect, in screenFrame: NSRect) -> CGFloat {
        max(0, min(rect.maxX, screenFrame.maxX - screenMargin) - max(rect.minX, screenFrame.minX + screenMargin))
    }
}

import AppKit

@main
struct BubblePlacementCheck {
    static func main() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let petCenter = NSPoint(x: 90, y: 220)
        let layout = BubblePlacement.resolve(
            petScreenCenter: petCenter,
            screenFrame: screen,
            windowSize: NSSize(width: 420, height: 300),
            petRectLeftBubble: NSRect(x: 257, y: 140, width: 123, height: 140),
            petRectRightBubble: NSRect(x: 40, y: 140, width: 123, height: 140),
            bubbleRectLeft: NSRect(x: 24, y: 18, width: 366, height: 96),
            bubbleRectRight: NSRect(x: 24, y: 18, width: 366, height: 96),
            currentSide: .left
        )

        precondition(layout.side == .right, "expected bubble to switch to the right near the left screen edge")
        precondition(layout.bubbleScreenRect.minX >= screen.minX + 8, "expected bubble to stay inside the left screen edge")
    }
}

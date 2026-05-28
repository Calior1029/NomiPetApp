import AppKit

@main
struct BubbleTextScrollerCheck {
    static func main() {
        let contentHeight: CGFloat = 120
        let viewportHeight: CGFloat = 40
        let maxOffset = contentHeight - viewportHeight

        precondition(BubbleTextScroller.verticalOffset(
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            elapsed: 0
        ) == 0)

        let travel = TimeInterval(maxOffset / BubbleTextScroller.scrollSpeed)
        let midOffset = BubbleTextScroller.verticalOffset(
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            elapsed: BubbleTextScroller.edgePause + travel / 2
        )
        precondition(midOffset > 0 && midOffset < maxOffset)

        let bottomOffset = BubbleTextScroller.verticalOffset(
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            elapsed: BubbleTextScroller.edgePause + travel + 0.1
        )
        precondition(abs(bottomOffset - maxOffset) < 0.01)

        let fittingOffset = BubbleTextScroller.verticalOffset(
            contentHeight: 36,
            viewportHeight: viewportHeight,
            elapsed: 999
        )
        precondition(fittingOffset == 0)
    }
}

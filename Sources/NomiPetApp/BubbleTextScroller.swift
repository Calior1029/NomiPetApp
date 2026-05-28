import AppKit

enum BubbleTextScroller {
    static let scrollSpeed: CGFloat = 18
    static let edgePause: TimeInterval = 1.15

    static func verticalOffset(
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        elapsed: TimeInterval
    ) -> CGFloat {
        let maxOffset = max(0, contentHeight - viewportHeight)
        guard maxOffset > 1 else { return 0 }

        let travelDuration = TimeInterval(maxOffset / scrollSpeed)
        guard travelDuration > 0 else { return 0 }

        let cycleDuration = edgePause + travelDuration + edgePause + travelDuration
        let cycleTime = elapsed.truncatingRemainder(dividingBy: cycleDuration)

        if cycleTime < edgePause {
            return 0
        }

        let scrollingDownEnd = edgePause + travelDuration
        if cycleTime < scrollingDownEnd {
            let progress = (cycleTime - edgePause) / travelDuration
            return maxOffset * CGFloat(progress)
        }

        let bottomPauseEnd = scrollingDownEnd + edgePause
        if cycleTime < bottomPauseEnd {
            return maxOffset
        }

        let progress = (cycleTime - bottomPauseEnd) / travelDuration
        return maxOffset * CGFloat(1 - progress)
    }
}

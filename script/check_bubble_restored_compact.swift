import AppKit

@main
struct BubbleRestoredCompactCheck {
    static func main() {
        let view = PetView(frame: NSRect(x: 0, y: 0, width: 700, height: 360))
        view.bubbleText = "桌宠开发\n这是一段比较长的 AI 回复，用来确认气泡不会因为内容变长就自动放大。"
        view.bubbleScale = 1.0

        view.bubbleStyle = .compact
        let compact = view.bubbleRect(for: .left).size

        view.bubbleStyle = .dynamic
        let dynamic = view.bubbleRect(for: .left).size

        precondition(dynamic == compact, "AI bubble should keep the same frame size as the previous compact bubble")
    }
}
